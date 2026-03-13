defmodule Jido.Integration.V2.DirectRuntime do
  @moduledoc """
  Executes direct capabilities through `Jido.Action` modules.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.RuntimeResult

  @type runtime_result :: RuntimeResult.t()

  @spec execute(Capability.t(), map(), map()) ::
          {:ok, runtime_result()} | {:error, term(), runtime_result()}
  def execute(%Capability{runtime_class: :direct, handler: handler} = capability, input, context) do
    base_events = [%{type: "attempt.started", payload: %{capability_id: capability.id}}]

    case handler.run(input, Map.put(context, :capability, capability)) do
      {:ok, result} ->
        {:ok,
         merge_runtime_result(
           base_events,
           [
             %{type: "attempt.completed", payload: %{handler: inspect(handler)}}
           ],
           result
         )}

      {:error, reason} ->
        {:error, reason,
         merge_runtime_result(
           base_events,
           [
             %{
               type: "attempt.failed",
               payload: %{handler: inspect(handler), reason: inspect(reason)}
             }
           ],
           nil
         )}

      {:error, reason, result} ->
        {:error, reason,
         merge_runtime_result(
           base_events,
           [
             %{
               type: "attempt.failed",
               payload: %{handler: inspect(handler), reason: inspect(reason)}
             }
           ],
           result
         )}
    end
  end

  defp merge_runtime_result(base_events, completion_events, %RuntimeResult{} = result) do
    %RuntimeResult{
      result
      | runtime_ref_id: nil,
        events: base_events ++ result.events ++ completion_events
    }
  end

  defp merge_runtime_result(base_events, completion_events, output) do
    RuntimeResult.new!(%{
      output: output,
      events: base_events ++ completion_events
    })
  end
end
