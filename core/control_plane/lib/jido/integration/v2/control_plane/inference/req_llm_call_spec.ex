defmodule Jido.Integration.V2.ControlPlane.Inference.ReqLLMCallSpec do
  @moduledoc false

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.InferenceExecutionContext
  alias Jido.Integration.V2.InferenceRequest

  defstruct model_spec: nil,
            operation: nil,
            base_url: nil,
            headers: %{},
            messages: [],
            prompt: nil,
            options: %{},
            observability: %{}

  @type t :: %__MODULE__{
          model_spec: map() | String.t(),
          operation: :generate_text | :stream_text,
          base_url: String.t() | nil,
          headers: %{optional(String.t()) => String.t()},
          messages: [map()],
          prompt: String.t() | nil,
          options: map(),
          observability: map()
        }

  @spec from_cloud_route(InferenceRequest.t(), InferenceExecutionContext.t() | map(), map()) ::
          t()
  def from_cloud_route(
        %InferenceRequest{} = request,
        context,
        route
      )
      when is_map(context) and is_map(route) do
    context = normalize_context(context)

    provider =
      route
      |> get_value(:provider)
      |> Contracts.normalize_atomish!("cloud_route.provider")

    model_id =
      route
      |> get_value(:id, get_value(route, :model))
      |> Contracts.validate_non_empty_string!("cloud_route.id")

    base_url =
      route
      |> get_value(:base_url)
      |> normalize_optional_string("cloud_route.base_url")

    options =
      request
      |> request_options()
      |> Map.merge(optional_map(route, :options))

    %__MODULE__{
      model_spec: compact_model_spec(%{provider: provider, id: model_id, base_url: base_url}),
      operation: request.operation,
      base_url: base_url,
      headers: %{},
      messages: request.messages,
      prompt: request.prompt,
      options: options,
      observability: Map.new(context.observability)
    }
  end

  @spec from_endpoint(
          InferenceRequest.t(),
          InferenceExecutionContext.t() | map(),
          EndpointDescriptor.t()
        ) ::
          t()
  def from_endpoint(
        %InferenceRequest{} = request,
        context,
        %EndpointDescriptor{} = endpoint
      )
      when is_map(context) do
    context = normalize_context(context)

    :openai_chat_completions = Contracts.validate_inference_protocol!(endpoint.protocol)
    {api_key, headers} = extract_api_key(endpoint.headers)

    options =
      request
      |> request_options()
      |> maybe_put_option(:api_key, api_key)

    %__MODULE__{
      model_spec:
        compact_model_spec(%{
          provider: protocol_provider(endpoint.protocol),
          id: endpoint.model_identity,
          base_url: endpoint.base_url
        }),
      operation: request.operation,
      base_url: endpoint.base_url,
      headers: headers,
      messages: request.messages,
      prompt: request.prompt,
      options: options,
      observability: Map.new(context.observability)
    }
  end

  defp request_options(%InferenceRequest{} = request) do
    %{}
    |> Map.merge(filter_known_options(request.model_preference))
    |> Map.merge(filter_known_options(request.output_constraints))
    |> maybe_put_option(:tools, get_value(request.tool_policy, :tools))
    |> maybe_put_option(:tool_choice, get_value(request.tool_policy, :tool_choice))
  end

  defp filter_known_options(nil), do: %{}

  defp filter_known_options(%{} = options) do
    options
    |> Map.new()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      normalized_key = normalize_option_key(key)

      if normalized_key in [
           :temperature,
           :max_tokens,
           :top_p,
           :presence_penalty,
           :frequency_penalty,
           :system_prompt,
           :provider_options
         ] do
        Map.put(acc, normalized_key, value)
      else
        acc
      end
    end)
  end

  defp filter_known_options(_value), do: %{}

  defp normalize_option_key(key) when is_atom(key), do: key

  defp normalize_option_key(key) when is_binary(key) do
    key
    |> String.replace("?", "")
    |> String.to_atom()
  end

  defp protocol_provider(:openai_chat_completions), do: :openai

  defp extract_api_key(headers) when is_map(headers) do
    headers = normalize_headers(headers)
    authorization = Map.get(headers, "authorization")

    case bearer_token(authorization) do
      nil -> {nil, headers}
      api_key -> {api_key, Map.delete(headers, "authorization")}
    end
  end

  defp normalize_headers(headers) do
    Enum.into(headers, %{}, fn {key, value} ->
      {String.downcase(to_string(key)), to_string(value)}
    end)
  end

  defp bearer_token("Bearer " <> token) when token != "", do: token
  defp bearer_token("bearer " <> token) when token != "", do: token
  defp bearer_token(_value), do: nil

  defp maybe_put_option(options, _key, nil), do: options
  defp maybe_put_option(options, key, value), do: Map.put(options, key, value)

  defp compact_model_spec(model_spec) do
    model_spec
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp get_value(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp get_value(_map, _key, default), do: default

  defp optional_map(map, key) do
    case get_value(map, key) do
      nil -> %{}
      %{} = value -> Map.new(value)
      other -> raise ArgumentError, "#{key} must be a map, got: #{inspect(other)}"
    end
  end

  defp normalize_optional_string(nil, _field_name), do: nil

  defp normalize_optional_string(value, field_name) do
    Contracts.validate_non_empty_string!(value, field_name)
  end

  defp normalize_context(%InferenceExecutionContext{} = context), do: context
  defp normalize_context(context), do: InferenceExecutionContext.new!(context)
end
