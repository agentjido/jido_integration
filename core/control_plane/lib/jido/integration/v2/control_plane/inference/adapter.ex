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
      prompt: prompt(request),
      model_preference: model_preference(client, request),
      target_preference: target_preference(client, request),
      stream?: operation == :stream_text,
      tool_policy: option_map(request, :tool_policy, %{}),
      output_constraints: output_constraints(request),
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

  defp prompt(%Request{} = request) do
    case Keyword.get(request.options, :prompt) do
      prompt when is_binary(prompt) and prompt != "" -> prompt
      _other -> nil
    end
  end

  defp model_preference(%Client{} = client, %Request{} = request) do
    request
    |> option_map(:model_preference, %{})
    |> Map.put_new(:provider, client.provider)
    |> Map.put_new(:id, request.model || client.model)
    |> reject_nil_values()
  end

  defp target_preference(%Client{} = client, %Request{} = request) do
    request
    |> option_map(:target_preference, %{})
    |> Map.merge(Map.new(Keyword.get(client.adapter_opts, :target_preference, %{})))
  end

  defp output_constraints(%Request{} = request) do
    request
    |> option_map(:output_constraints, %{})
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
    client.adapter_opts
    |> Keyword.get(:invoke_opts, [])
    |> Keyword.merge(Keyword.get(request.options, :invoke_opts, []))
    |> maybe_put(:trace_id, trace_value(request, :trace_id))
    |> maybe_put(:span_id, trace_value(request, :span_id))
    |> maybe_put(:correlation_id, trace_value(request, :correlation_id))
    |> maybe_put(:causation_id, trace_value(request, :causation_id))
    |> maybe_put(:context_metadata, option_map(request, :context_metadata, nil))
    |> maybe_put(:consumer_metadata, option_map(request, :consumer_metadata, nil))
    |> maybe_put(:target_backend_options, option_map(request, :target_backend_options, nil))
    |> maybe_put(:credential_scope, option_map(request, :credential_scope, nil))
    |> maybe_put(:api_key, Keyword.get(request.options, :api_key))
  end

  defp response_from_invocation({:ok, result}, %Client{} = client, %Request{} = request) do
    {:ok,
     Response.new(
       provider: client.provider,
       model: request.model || client.model,
       text: response_text(result),
       usage: result_field(result, [:inference_result, :usage]),
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

  defp option_map(%Request{options: options}, key, default) do
    case Keyword.get(options, key, default) do
      nil -> default
      value when is_map(value) -> value
      value when is_list(value) -> Map.new(value)
      _other -> default
    end
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
  defp field(value, key) when is_map(value), do: value[key] || value[to_string(key)]
  defp field(_value, _key), do: nil

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
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
