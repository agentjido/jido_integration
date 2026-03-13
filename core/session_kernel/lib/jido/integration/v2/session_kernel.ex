defmodule Jido.Integration.V2.SessionKernel do
  @moduledoc """
  Reusable session runtime for interactive capabilities.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.RuntimeResult
  alias Jido.Integration.V2.SessionKernel.SessionStore

  @type runtime_result :: RuntimeResult.t()

  @spec execute(Capability.t(), map(), map()) ::
          {:ok, runtime_result()} | {:error, term(), runtime_result()}
  def execute(
        %Capability{runtime_class: :session, handler: provider} = capability,
        input,
        context
      ) do
    key = provider.reuse_key(capability, context)

    {session, session_event_type} =
      case SessionStore.fetch(key) do
        {:ok, existing_session} ->
          {existing_session, "session.reused"}

        :error ->
          {:ok, new_session} = provider.open_session(capability, context)
          SessionStore.put(key, new_session)
          {new_session, "session.started"}
      end

    base_events = [
      %{type: "attempt.started", payload: %{capability_id: capability.id}},
      %{
        type: session_event_type,
        payload: %{provider: inspect(provider)},
        runtime_ref_id: session.session_id
      }
    ]

    case provider.execute(capability, session, input, context) do
      {:ok, output, updated_session} ->
        runtime_result = normalize_runtime_result(output, updated_session.session_id)
        SessionStore.put(key, updated_session)

        {:ok,
         %RuntimeResult{
           runtime_result
           | events:
               base_events ++
                 runtime_result.events ++
                 [
                   %{
                     type: "attempt.completed",
                     payload: %{provider: inspect(provider)},
                     runtime_ref_id: updated_session.session_id
                   }
                 ]
         }}

      {:error, reason, updated_session} ->
        SessionStore.put(key, updated_session)

        {:error, reason,
         %{
           output: nil,
           runtime_ref_id: updated_session.session_id,
           events:
             base_events ++
               [
                 %{
                   type: "attempt.failed",
                   payload: %{provider: inspect(provider), reason: inspect(reason)},
                   runtime_ref_id: updated_session.session_id
                 }
               ]
         }}
    end
  end

  @spec reset!() :: :ok
  def reset! do
    SessionStore.reset!()
    :ok
  end

  defp normalize_runtime_result(%RuntimeResult{} = runtime_result, session_id) do
    %RuntimeResult{
      runtime_result
      | runtime_ref_id: runtime_result.runtime_ref_id || session_id,
        events: attach_runtime_ref(runtime_result.events, session_id)
    }
  end

  defp normalize_runtime_result(output, session_id) do
    RuntimeResult.new!(%{
      output: output,
      runtime_ref_id: session_id
    })
  end

  defp attach_runtime_ref(events, runtime_ref_id) do
    Enum.map(events, fn event ->
      Map.put_new(event, :runtime_ref_id, runtime_ref_id)
    end)
  end
end
