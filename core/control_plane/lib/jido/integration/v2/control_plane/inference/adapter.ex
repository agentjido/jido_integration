defmodule Jido.Integration.V2.ControlPlane.Inference.Adapter do
  @moduledoc """
  Jido-owned adapter for the shared `:inference` package.

  This adapter is the boundary used by external libraries that speak
  `Inference.Client`/`Inference.Request` but need Jido Integration's governed
  control-plane execution, durable run truth, policy metadata, route metadata,
  credential scope, replay metadata, and review projection.
  """

  @behaviour Inference.Adapter

  alias Inference.{Client, Error, Request, Response, StreamEvent}
  alias Jido.Integration.V2.ControlPlane.Inference, as: GovernedInference
  alias Jido.Integration.V2.InferenceRequest

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    invoke(client, request, :generate_text)
    |> response_from_invocation(client, request)
  end

  @impl true
  def stream(%Client{} = client, %Request{} = request) do
    case invoke(client, request, :stream_text) do
      {:ok, result} ->
        {:ok,
         result
         |> response_text()
         |> stream_events()}

      {:error, reason} ->
        {:error, normalize_error(reason)}
    end
  end

  defp invoke(%Client{} = client, %Request{} = request, operation) do
    with {:ok, governed_request} <- governed_request(client, request, operation) do
      invoke_fun = Keyword.get(client.adapter_opts, :invoke_fun, &GovernedInference.invoke/2)
      invoke_fun.(governed_request, invoke_opts(client, request))
    end
  rescue
    exception -> {:error, Error.adapter_exception(exception, adapter: __MODULE__)}
  end

  defp governed_request(%Client{} = client, %Request{} = request, operation) do
    InferenceRequest.new(
      request_id: request.id || generated_request_id(),
      operation: operation,
      messages: messages(request),
      prompt: prompt(client, request),
      model_preference: model_preference(client, request),
      target_preference: target_preference(client, request),
      stream?: operation == :stream_text,
      tool_policy: tool_policy(client, request),
      output_constraints: output_constraints(client, request),
      metadata: metadata(client, request)
    )
  end

  defp messages(%Request{messages: messages}) do
    Enum.map(messages, fn message ->
      %{
        role: Atom.to_string(message.role),
        content: message.content
      }
      |> maybe_put(:name, message.name)
      |> maybe_put(:metadata, empty_to_nil(message.metadata))
    end)
  end

  defp prompt(%Client{} = client, %Request{} = request) do
    case option_value(client, request, :prompt) do
      prompt when is_binary(prompt) and prompt != "" -> prompt
      _other -> nil
    end
  end

  defp model_preference(%Client{} = client, %Request{} = request) do
    client
    |> option_map(request, :model_preference, %{})
    |> Map.put_new(:provider, client.provider)
    |> Map.put_new(:id, request.model || client.model)
    |> reject_nil_values()
  end

  defp target_preference(%Client{} = client, %Request{} = request) do
    client_target_preference =
      client.adapter_opts
      |> Keyword.get(:target_preference, %{})
      |> map_or_empty()

    request_target_preference = option_map(client, request, :target_preference, %{})

    Map.merge(client_target_preference, request_target_preference)
  end

  defp tool_policy(%Client{} = client, %Request{} = request) do
    request_options = request_options(client, request)

    client
    |> option_map(request, :tool_policy, %{})
    |> maybe_put(:tools, Keyword.get(request_options, :tools))
    |> maybe_put(:tool_choice, Keyword.get(request_options, :tool_choice))
  end

  defp output_constraints(%Client{} = client, %Request{} = request) do
    request_options = request_options(client, request)

    request_options
    |> option_map(:output_constraints, %{})
    |> maybe_put(:frequency_penalty, Keyword.get(request_options, :frequency_penalty))
    |> maybe_put(:presence_penalty, Keyword.get(request_options, :presence_penalty))
    |> maybe_put(:provider_options, option_map(request_options, :provider_options, nil))
    |> maybe_put(:system_prompt, Keyword.get(request_options, :system_prompt))
    |> maybe_put(:temperature, request.temperature)
    |> maybe_put(:top_p, request.top_p)
    |> maybe_put(:max_tokens, request.max_tokens)
    |> maybe_put(:response_format, request.response_format)
  end

  defp metadata(%Client{} = client, %Request{} = request) do
    client.metadata
    |> Map.merge(request.metadata)
    |> maybe_put(:trace_context, request.trace_context)
    |> maybe_put(:session, request.session)
  end

  defp invoke_opts(%Client{} = client, %Request{} = request) do
    request_options = request_options(client, request)

    client.adapter_opts
    |> Keyword.get(:invoke_opts, [])
    |> Keyword.merge(Keyword.get(request_options, :invoke_opts, []))
    |> maybe_put(:trace_id, trace_value(request, :trace_id))
    |> maybe_put(:span_id, trace_value(request, :span_id))
    |> maybe_put(:correlation_id, trace_value(request, :correlation_id))
    |> maybe_put(:causation_id, trace_value(request, :causation_id))
    |> maybe_put(:context_metadata, option_map(request_options, :context_metadata, nil))
    |> maybe_put(:consumer_metadata, option_map(request_options, :consumer_metadata, nil))
    |> maybe_put(
      :target_backend_options,
      option_map(request_options, :target_backend_options, nil)
    )
    |> maybe_put(:credential_scope, option_map(request_options, :credential_scope, nil))
    |> maybe_put(:api_key, Keyword.get(request_options, :api_key))
    |> maybe_put(:req_http_options, Keyword.get(request_options, :req_http_options))
  end

  defp response_from_invocation({:ok, result}, %Client{} = client, %Request{} = request) do
    {:ok,
     Response.new(
       provider: client.provider,
       model: request.model || client.model,
       text: response_text(result),
       usage: result_field(result, [:inference_result, :usage]),
       cost: result_cost(result),
       finish_reason: result_field(result, [:inference_result, :finish_reason]),
       raw: result,
       metadata: response_metadata(result, client, request)
     )}
  end

  defp response_from_invocation({:error, reason}, _client, _request) do
    {:error, normalize_error(reason)}
  end

  defp response_metadata(result, %Client{} = client, %Request{} = request) do
    %{}
    |> Map.merge(client.metadata)
    |> Map.merge(request.metadata)
    |> maybe_put(:run_id, result_field(result, [:inference_result, :run_id]))
    |> maybe_put(:attempt_id, result_field(result, [:inference_result, :attempt_id]))
    |> maybe_put(:status, result_field(result, [:inference_result, :status]))
    |> maybe_put(:streaming?, result_field(result, [:inference_result, :streaming?]))
    |> maybe_put(:endpoint_id, result_field(result, [:inference_result, :endpoint_id]))
    |> maybe_put(:route, result_field(result, [:compatibility_result, :metadata, :route]))
    |> maybe_put(:lease_ref, result_field(result, [:lease_ref, :lease_ref]))
  end

  defp response_text(result) do
    case result_field(result, [:response_text]) do
      text when is_binary(text) -> text
      _other -> ""
    end
  end

  defp result_cost(result) do
    result_field(result, [:response_summary, :cost]) ||
      result_field(result, [:inference_result, :metadata, :cost]) ||
      result_field(result, [:inference_result, :usage, :cost]) ||
      result_field(result, [:inference_result, :usage, :total_cost])
  end

  defp stream_events(""), do: [%StreamEvent{type: :done, data: nil}]

  defp stream_events(text) do
    [
      %StreamEvent{type: :delta, data: text},
      %StreamEvent{type: :done, data: nil}
    ]
  end

  defp normalize_error(%Error{} = error), do: error

  defp normalize_error(reason) do
    Error.provider_error(reason, adapter: __MODULE__)
  end

  defp option_map(%Client{} = client, %Request{} = request, key, default),
    do: option_map(request_options(client, request), key, default)

  defp option_map(options, key, default) when is_list(options) do
    case Keyword.get(options, key, default) do
      nil -> default
      value when is_map(value) -> value
      value when is_list(value) -> Map.new(value)
      _other -> default
    end
  end

  defp map_or_empty(nil), do: %{}
  defp map_or_empty(value) when is_map(value), do: value
  defp map_or_empty(value) when is_list(value), do: Map.new(value)
  defp map_or_empty(_value), do: %{}

  defp request_options(%Client{} = client, %Request{} = request) do
    Keyword.merge(client.defaults, request.options)
  end

  defp trace_value(%Request{trace_context: trace_context}, key) when is_map(trace_context) do
    trace_context[key] || trace_context[to_string(key)]
  end

  defp trace_value(_request, _key), do: nil

  defp result_field(result, path) do
    Enum.reduce_while(path, result, fn key, acc ->
      case field(acc, key) do
        nil -> {:halt, nil}
        value -> {:cont, value}
      end
    end)
  end

  defp field(%_struct{} = value, key), do: Map.get(value, key)

  defp field(value, key) when is_map(value) do
    cond do
      Map.has_key?(value, key) -> Map.fetch!(value, key)
      Map.has_key?(value, to_string(key)) -> Map.fetch!(value, to_string(key))
      true -> nil
    end
  end

  defp field(_value, _key), do: nil

  defp option_value(%Client{} = client, %Request{} = request, key) do
    client
    |> request_options(request)
    |> Keyword.get(key)
  end

  defp generated_request_id do
    "req-inference-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp empty_to_nil(map) when map == %{}, do: nil
  defp empty_to_nil(map), do: map

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(opts, key, value) when is_list(opts), do: Keyword.put(opts, key, value)
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
