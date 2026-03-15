defmodule Jido.Integration.V2.StreamRuntime.HarnessDriver do
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
  alias Jido.Integration.V2.StreamRuntime.Store

  @runtime_id :integration_stream_bridge

  @spec reuse_key(Capability.t(), map(), map(), map()) :: term()
  def reuse_key(%Capability{handler: provider} = capability, input, context, _runtime_config) do
    provider.reuse_key(capability, input, context)
  end

  @impl true
  def runtime_id, do: @runtime_id

  @impl true
  def runtime_descriptor(_opts \\ []) do
    RuntimeDescriptor.new!(%{
      runtime_id: @runtime_id,
      provider: nil,
      label: "Integration Stream Bridge",
      session_mode: :internal,
      streaming?: false,
      cancellation?: false,
      approvals?: false,
      cost?: false,
      subscribe?: false,
      resume?: false,
      metadata: %{"bridge" => "stream_runtime"}
    })
  end

  @impl true
  def start_session(opts) when is_list(opts) do
    capability = Keyword.fetch!(opts, :capability)
    context = Keyword.fetch!(opts, :context)
    input = Keyword.fetch!(opts, :input)
    provider = capability.handler

    with {:ok, stream} <- provider.open_stream(capability, input, context),
         :ok <- store_stream(stream) do
      {:ok,
       SessionHandle.new!(%{
         session_id: stream.stream_id,
         runtime_id: @runtime_id,
         provider: nil,
         status: :ready,
         driver_ref: stream.stream_id,
         metadata: %{"capability_id" => capability.id}
       })}
    end
  end

  @impl true
  def stop_session(%SessionHandle{session_id: session_id}) do
    Store.delete(storage_key(session_id))
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
      case Store.fetch(storage_key(session_id)) do
        {:ok, _stream} -> :ready
        :error -> :stopped
      end

    {:ok,
     ExecutionStatus.new!(%{
       runtime_id: @runtime_id,
       session_id: session_id,
       scope: :session,
       state: state,
       timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
       details: %{"bridge" => "stream_runtime"}
     })}
  end

  defp execute_runtime(%SessionHandle{session_id: session_id}, opts) do
    capability = Keyword.fetch!(opts, :capability)
    context = Keyword.fetch!(opts, :context)
    input = Keyword.fetch!(opts, :input)
    lifecycle = Keyword.get(opts, :lifecycle, :started)

    with {:ok, stream} <- fetch_stream(session_id) do
      case capability.handler.pull(capability, stream, input, context) do
        {:ok, output, updated_stream} ->
          runtime_result =
            output
            |> normalize_runtime_result(updated_stream.stream_id, lifecycle)
            |> store_stream!(updated_stream)

          {:ok, runtime_result, :completed}

        {:error, reason, updated_stream} ->
          runtime_result =
            RuntimeResult.new!(%{
              output: nil,
              runtime_ref_id: updated_stream.stream_id,
              events: [
                %{
                  type: "attempt.started",
                  payload: %{capability_id: capability.id},
                  session_id: updated_stream.stream_id,
                  runtime_ref_id: updated_stream.stream_id
                },
                %{
                  type: lifecycle_event_type(lifecycle),
                  payload: %{provider: inspect(capability.handler)},
                  session_id: updated_stream.stream_id,
                  runtime_ref_id: updated_stream.stream_id
                },
                %{
                  type: "attempt.failed",
                  payload: %{provider: inspect(capability.handler), reason: inspect(reason)},
                  session_id: updated_stream.stream_id,
                  runtime_ref_id: updated_stream.stream_id
                }
              ]
            })
            |> store_stream!(updated_stream)

          {:error, reason, runtime_result}
      end
    end
  end

  defp normalize_runtime_result(%RuntimeResult{} = runtime_result, stream_id, lifecycle) do
    %RuntimeResult{
      runtime_result
      | runtime_ref_id: runtime_result.runtime_ref_id || stream_id,
        events:
          [
            %{
              type: "attempt.started",
              payload: %{},
              session_id: stream_id,
              runtime_ref_id: stream_id
            },
            %{
              type: lifecycle_event_type(lifecycle),
              payload: %{},
              session_id: stream_id,
              runtime_ref_id: stream_id
            }
          ] ++
            Enum.map(runtime_result.events, fn event ->
              event
              |> Map.put_new(:session_id, stream_id)
              |> Map.put_new(:runtime_ref_id, stream_id)
            end) ++
            [
              %{
                type: "attempt.completed",
                payload: %{},
                session_id: stream_id,
                runtime_ref_id: stream_id
              }
            ]
    }
  end

  defp normalize_runtime_result(output, stream_id, lifecycle) do
    RuntimeResult.new!(%{
      output: output,
      runtime_ref_id: stream_id,
      events: [
        %{
          type: "attempt.started",
          payload: %{},
          session_id: stream_id,
          runtime_ref_id: stream_id
        },
        %{
          type: lifecycle_event_type(lifecycle),
          payload: %{},
          session_id: stream_id,
          runtime_ref_id: stream_id
        },
        %{
          type: "attempt.completed",
          payload: %{},
          session_id: stream_id,
          runtime_ref_id: stream_id
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

  defp lifecycle_event_type(:started), do: "stream.started"
  defp lifecycle_event_type(:reused), do: "stream.reused"

  defp output_text(%RuntimeResult{output: output}) when is_map(output) do
    Map.get(output, :text) || Map.get(output, "text")
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

  defp store_stream(stream) do
    Store.put(storage_key(stream.stream_id), stream)
    :ok
  end

  defp store_stream!(%RuntimeResult{} = runtime_result, updated_stream) do
    :ok = store_stream(updated_stream)
    runtime_result
  end

  defp fetch_stream(stream_id) do
    case Store.fetch(storage_key(stream_id)) do
      {:ok, stream} -> {:ok, stream}
      :error -> {:error, :unknown_stream}
    end
  end

  defp storage_key(stream_id), do: {:stream_id, stream_id}

  defp maybe_drop_failure_reason(metadata, nil) do
    update_in(metadata, ["jido_integration"], &Map.delete(&1, "failure_reason"))
  end

  defp maybe_drop_failure_reason(metadata, _reason), do: metadata

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
