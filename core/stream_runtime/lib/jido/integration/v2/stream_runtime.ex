defmodule Jido.Integration.V2.StreamRuntime do
  @moduledoc """
  Pull-oriented runtime for feed and protocol capabilities.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.RuntimeResult
  alias Jido.Integration.V2.StreamRuntime.Store

  @type runtime_result :: RuntimeResult.t()

  @spec execute(Capability.t(), map(), map()) ::
          {:ok, runtime_result()} | {:error, term(), runtime_result()}
  def execute(%Capability{runtime_class: :stream, handler: provider} = capability, input, context) do
    key = provider.reuse_key(capability, input, context)

    {stream, stream_event_type} =
      case Store.fetch(key) do
        {:ok, existing_stream} ->
          {existing_stream, "stream.reused"}

        :error ->
          {:ok, new_stream} = provider.open_stream(capability, input, context)
          Store.put(key, new_stream)
          {new_stream, "stream.started"}
      end

    base_events = [
      %{type: "attempt.started", payload: %{capability_id: capability.id}},
      %{
        type: stream_event_type,
        payload: %{provider: inspect(provider)},
        runtime_ref_id: stream.stream_id
      }
    ]

    case provider.pull(capability, stream, input, context) do
      {:ok, output, updated_stream} ->
        runtime_result = normalize_runtime_result(output, updated_stream.stream_id)
        Store.put(key, updated_stream)

        {:ok,
         %RuntimeResult{
           runtime_result
           | output:
               runtime_result.output &&
                 Map.put(runtime_result.output, :stream_id, updated_stream.stream_id),
             events:
               base_events ++
                 runtime_result.events ++
                 [
                   %{
                     type: "attempt.completed",
                     payload: %{provider: inspect(provider)},
                     runtime_ref_id: updated_stream.stream_id
                   }
                 ]
         }}

      {:error, reason, updated_stream} ->
        Store.put(key, updated_stream)

        {:error, reason,
         %{
           output: nil,
           runtime_ref_id: updated_stream.stream_id,
           events:
             base_events ++
               [
                 %{
                   type: "attempt.failed",
                   payload: %{provider: inspect(provider), reason: inspect(reason)},
                   runtime_ref_id: updated_stream.stream_id
                 }
               ]
         }}
    end
  end

  @spec reset!() :: :ok
  def reset! do
    Store.reset!()
  end

  defp normalize_runtime_result(%RuntimeResult{} = runtime_result, stream_id) do
    %RuntimeResult{
      runtime_result
      | runtime_ref_id: runtime_result.runtime_ref_id || stream_id,
        events: attach_runtime_ref(runtime_result.events, stream_id)
    }
  end

  defp normalize_runtime_result(output, stream_id) do
    RuntimeResult.new!(%{
      output: output,
      runtime_ref_id: stream_id
    })
  end

  defp attach_runtime_ref(events, runtime_ref_id) do
    Enum.map(events, fn event ->
      Map.put_new(event, :runtime_ref_id, runtime_ref_id)
    end)
  end
end
