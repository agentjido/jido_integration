defmodule Jido.Integration.V2.SessionKernel.HarnessDriver do
  @moduledoc false

  @behaviour Jido.Harness.RuntimeDriver

  alias Jido.Harness.{
    ExecutionEvent,
    ExecutionResult,
    ExecutionStatus,
    RunHandle,
    RunRequest,
    RuntimeDescriptor,
    SessionHandle
  }

  alias Jido.Integration.V2.{Capability, RuntimeResult}
  alias Jido.Integration.V2.SessionKernel.SessionStore

  @runtime_id :integration_session_bridge

  @spec reuse_key(Capability.t(), map(), map(), map()) :: term()
  def reuse_key(%Capability{handler: provider} = capability, _input, context, _runtime_config) do
    provider.reuse_key(capability, context)
  end

  @impl true
  def runtime_id, do: @runtime_id

  @impl true
  def runtime_descriptor(_opts \\ []) do
    RuntimeDescriptor.new!(%{
      runtime_id: @runtime_id,
      provider: nil,
      label: "Integration Session Bridge",
      session_mode: :internal,
      streaming?: false,
      cancellation?: false,
      approvals?: false,
      cost?: false,
      subscribe?: false,
      resume?: false,
      metadata: %{"bridge" => "session_kernel"}
    })
  end

  @impl true
  def start_session(opts) when is_list(opts) do
    capability = Keyword.fetch!(opts, :capability)
    context = Keyword.fetch!(opts, :context)
    provider = capability.handler

    with {:ok, session} <- provider.open_session(capability, context),
         :ok <- store_session(session) do
      {:ok,
       SessionHandle.new!(%{
         session_id: session.session_id,
         runtime_id: @runtime_id,
         provider: nil,
         status: :ready,
         driver_ref: session.session_id,
         metadata: %{"capability_id" => capability.id}
       })}
    end
  end

  @impl true
  def stop_session(%SessionHandle{session_id: session_id}) do
    SessionStore.delete(storage_key(session_id))
    :ok
  end

  @impl true
  def stream_run(%SessionHandle{} = session, %RunRequest{} = _request, opts) when is_list(opts) do
    with {:ok, runtime_result, run_status} <- execute_runtime(session, opts) do
      {:ok, run_handle(session, opts, run_status), runtime_events(runtime_result, session, opts)}
    else
      {:error, _reason, runtime_result} ->
        {:ok, run_handle(session, opts, :failed), runtime_events(runtime_result, session, opts)}

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def run(%SessionHandle{} = session, %RunRequest{} = _request, opts) when is_list(opts) do
    case execute_runtime(session, opts) do
      {:ok, runtime_result, run_status} ->
        {:ok, execution_result(session, opts, runtime_result, run_status)}

      {:error, reason, runtime_result} ->
        {:ok, execution_result(session, opts, runtime_result, :failed, reason)}

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def cancel_run(_session, _run_or_id), do: :ok

  @impl true
  def session_status(%SessionHandle{session_id: session_id}) do
    state =
      case SessionStore.fetch(storage_key(session_id)) do
        {:ok, _session} -> :ready
        :error -> :stopped
      end

    {:ok,
     ExecutionStatus.new!(%{
       runtime_id: @runtime_id,
       session_id: session_id,
       scope: :session,
       state: state,
       timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
       details: %{"bridge" => "session_kernel"}
     })}
  end

  defp execute_runtime(%SessionHandle{session_id: session_id}, opts) do
    capability = Keyword.fetch!(opts, :capability)
    context = Keyword.fetch!(opts, :context)
    input = Keyword.fetch!(opts, :input)
    lifecycle = Keyword.get(opts, :lifecycle, :started)

    with {:ok, session} <- fetch_session(session_id) do
      case capability.handler.execute(capability, session, input, context) do
        {:ok, output, updated_session} ->
          runtime_result =
            output
            |> normalize_runtime_result(updated_session.session_id, lifecycle)
            |> store_session!(updated_session)

          {:ok, runtime_result, :completed}

        {:error, reason, updated_session} ->
          runtime_result =
            RuntimeResult.new!(%{
              output: nil,
              runtime_ref_id: updated_session.session_id,
              events: [
                %{
                  type: "attempt.started",
                  payload: %{capability_id: capability.id},
                  session_id: updated_session.session_id,
                  runtime_ref_id: updated_session.session_id
                },
                %{
                  type: lifecycle_event_type(lifecycle),
                  payload: %{provider: inspect(capability.handler)},
                  session_id: updated_session.session_id,
                  runtime_ref_id: updated_session.session_id
                },
                %{
                  type: "attempt.failed",
                  payload: %{provider: inspect(capability.handler), reason: inspect(reason)},
                  session_id: updated_session.session_id,
                  runtime_ref_id: updated_session.session_id
                }
              ]
            })
            |> store_session!(updated_session)

          {:error, reason, runtime_result}
      end
    end
  end

  defp normalize_runtime_result(%RuntimeResult{} = runtime_result, session_id, lifecycle) do
    %RuntimeResult{
      runtime_result
      | runtime_ref_id: runtime_result.runtime_ref_id || session_id,
        events:
          [
            %{
              type: "attempt.started",
              payload: %{},
              session_id: session_id,
              runtime_ref_id: session_id
            },
            %{
              type: lifecycle_event_type(lifecycle),
              payload: %{},
              session_id: session_id,
              runtime_ref_id: session_id
            }
          ] ++
            Enum.map(runtime_result.events, fn event ->
              event
              |> Map.put_new(:session_id, session_id)
              |> Map.put_new(:runtime_ref_id, session_id)
            end) ++
            [
              %{
                type: "attempt.completed",
                payload: %{},
                session_id: session_id,
                runtime_ref_id: session_id
              }
            ]
    }
  end

  defp normalize_runtime_result(output, session_id, lifecycle) do
    RuntimeResult.new!(%{
      output: output,
      runtime_ref_id: session_id,
      events: [
        %{
          type: "attempt.started",
          payload: %{},
          session_id: session_id,
          runtime_ref_id: session_id
        },
        %{
          type: lifecycle_event_type(lifecycle),
          payload: %{},
          session_id: session_id,
          runtime_ref_id: session_id
        },
        %{
          type: "attempt.completed",
          payload: %{},
          session_id: session_id,
          runtime_ref_id: session_id
        }
      ]
    })
  end

  defp execution_result(
         %SessionHandle{session_id: session_id},
         opts,
         %RuntimeResult{} = runtime_result,
         status,
         failure_reason \\ nil
       ) do
    metadata =
      %{
        "jido_integration" => %{
          "runtime_result" => runtime_result,
          "failure_reason" => failure_reason
        },
        "capability_id" => Keyword.fetch!(opts, :capability).id
      }
      |> maybe_drop_failure_reason(failure_reason)

    ExecutionResult.new!(%{
      run_id: Keyword.fetch!(opts, :run_id),
      session_id: session_id,
      runtime_id: @runtime_id,
      provider: nil,
      status: status,
      text: output_text(runtime_result),
      messages: [],
      cost: %{},
      stop_reason: stop_reason(status),
      metadata: metadata
    })
  end

  defp run_handle(%SessionHandle{session_id: session_id}, opts, status) do
    RunHandle.new!(%{
      run_id: Keyword.fetch!(opts, :run_id),
      session_id: session_id,
      runtime_id: @runtime_id,
      provider: nil,
      status: status,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      metadata: %{}
    })
  end

  defp runtime_events(
         %RuntimeResult{} = runtime_result,
         %SessionHandle{session_id: session_id},
         opts
       ) do
    runtime_result.events
    |> Enum.with_index(1)
    |> Enum.map(fn {event, index} ->
      ExecutionEvent.new!(%{
        event_id: "#{Keyword.fetch!(opts, :run_id)}:#{index}",
        type: execution_event_type(event.type),
        session_id: session_id,
        run_id: Keyword.fetch!(opts, :run_id),
        runtime_id: @runtime_id,
        provider: nil,
        sequence: index,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        payload: normalize_payload(event),
        metadata: %{"event_type" => event.type}
      })
    end)
    |> Stream.map(& &1)
  end

  defp execution_event_type("attempt.started"), do: :run_started
  defp execution_event_type("attempt.completed"), do: :result
  defp execution_event_type("attempt.failed"), do: :error
  defp execution_event_type(_other), do: :runtime_event

  defp lifecycle_event_type(:started), do: "session.started"
  defp lifecycle_event_type(:reused), do: "session.reused"

  defp output_text(%RuntimeResult{output: output}) when is_map(output) do
    Map.get(output, :reply) || Map.get(output, "reply") || Map.get(output, :text) ||
      Map.get(output, "text")
  end

  defp output_text(_runtime_result), do: nil

  defp stop_reason(:completed), do: "completed"
  defp stop_reason(_status), do: "failed"

  defp normalize_payload(event) do
    %{}
    |> maybe_put("type", event.type)
    |> maybe_put("payload", Map.get(event, :payload, %{}))
    |> maybe_put("runtime_ref_id", Map.get(event, :runtime_ref_id))
  end

  defp store_session(session) do
    SessionStore.put(storage_key(session.session_id), session)
    :ok
  end

  defp store_session!(%RuntimeResult{} = runtime_result, updated_session) do
    :ok = store_session(updated_session)
    runtime_result
  end

  defp fetch_session(session_id) do
    case SessionStore.fetch(storage_key(session_id)) do
      {:ok, session} -> {:ok, session}
      :error -> {:error, :unknown_session}
    end
  end

  defp storage_key(session_id), do: {:session_id, session_id}

  defp maybe_drop_failure_reason(metadata, nil) do
    update_in(metadata, ["jido_integration"], &Map.delete(&1, "failure_reason"))
  end

  defp maybe_drop_failure_reason(metadata, _reason), do: metadata

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
