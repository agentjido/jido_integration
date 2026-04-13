defmodule Jido.Session.RuntimeControlProjection do
  @moduledoc """
  Projects internal `jido_session` state into Runtime Control IR structs.
  """

  alias Jido.RuntimeControl.{
    ExecutionEvent,
    ExecutionResult,
    ExecutionStatus,
    RunHandle,
    RuntimeDescriptor,
    SessionHandle
  }

  alias Jido.Session.Runtime.{Run, Session}

  @spec runtime_descriptor(keyword()) :: RuntimeDescriptor.t()
  def runtime_descriptor(opts \\ []) do
    RuntimeDescriptor.new!(%{
      runtime_id: :jido_session,
      provider: Keyword.get(opts, :provider, :jido_session),
      label: "Jido Session",
      session_mode: :internal,
      streaming?: true,
      cancellation?: true,
      approvals?: false,
      cost?: false,
      subscribe?: false,
      resume?: false,
      metadata: %{
        "execution_model" => "app_controlled",
        "session_type" => "local_echo"
      }
    })
  end

  @spec session_handle(Session.t()) :: SessionHandle.t()
  def session_handle(%Session{} = session) do
    SessionHandle.new!(%{
      session_id: session.session_id,
      runtime_id: :jido_session,
      provider: session.provider,
      status: session.status,
      metadata:
        %{
          "cwd" => session.cwd,
          "session_type" => Atom.to_string(session.session_type)
        }
        |> maybe_put_map("boundary", boundary_metadata(session))
    })
  end

  @spec run_handle(Run.t()) :: RunHandle.t()
  def run_handle(%Run{} = run) do
    RunHandle.new!(%{
      run_id: run.run_id,
      session_id: run.session_id,
      runtime_id: :jido_session,
      provider: run.provider,
      status: run.status,
      started_at: run.started_at,
      metadata: %{
        "prompt" => run.prompt
      }
    })
  end

  @spec session_status(Session.t()) :: ExecutionStatus.t()
  def session_status(%Session{} = session) do
    ExecutionStatus.new!(%{
      runtime_id: :jido_session,
      session_id: session.session_id,
      scope: :session,
      state: session.status,
      timestamp: session.updated_at,
      details:
        %{
          "cwd" => session.cwd,
          "run_count" => length(session.run_ids)
        }
        |> maybe_put_map("boundary", boundary_metadata(session))
    })
  end

  @spec events(Session.t(), Run.t()) :: [ExecutionEvent.t()]
  def events(%Session{} = session, %Run{} = run) do
    [
      ExecutionEvent.new!(%{
        event_id: "#{run.run_id}:1",
        type: :run_started,
        session_id: session.session_id,
        run_id: run.run_id,
        runtime_id: :jido_session,
        provider: session.provider,
        sequence: 1,
        timestamp: run.started_at,
        status: :running,
        payload: %{
          "prompt" => run.prompt,
          "session_type" => Atom.to_string(session.session_type)
        }
      }),
      ExecutionEvent.new!(%{
        event_id: "#{run.run_id}:2",
        type: :assistant_message,
        session_id: session.session_id,
        run_id: run.run_id,
        runtime_id: :jido_session,
        provider: session.provider,
        sequence: 2,
        timestamp: run.completed_at || run.started_at,
        status: :running,
        payload: %{
          "role" => "assistant",
          "content" => run.result_text
        }
      }),
      ExecutionEvent.new!(%{
        event_id: "#{run.run_id}:3",
        type: :result,
        session_id: session.session_id,
        run_id: run.run_id,
        runtime_id: :jido_session,
        provider: session.provider,
        sequence: 3,
        timestamp: run.completed_at || run.started_at,
        status: run.status,
        payload: %{
          "text" => run.result_text,
          "message_count" => length(run.messages),
          "request_metadata" => run.request_metadata
        }
      })
    ]
  end

  @spec result(Session.t(), Run.t()) :: ExecutionResult.t()
  def result(%Session{} = session, %Run{} = run) do
    ExecutionResult.new!(%{
      run_id: run.run_id,
      session_id: session.session_id,
      runtime_id: :jido_session,
      provider: session.provider,
      status: run.status,
      text: run.result_text,
      messages: run.messages,
      cost: %{},
      duration_ms: run.duration_ms,
      stop_reason: run.stop_reason,
      metadata:
        Map.merge(run.metadata, %{
          "cwd" => session.cwd,
          "session_type" => Atom.to_string(session.session_type)
        })
        |> maybe_put_map("boundary", boundary_metadata(session))
    })
  end

  defp boundary_metadata(%Session{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "boundary") || Map.get(metadata, :boundary)
  end

  defp boundary_metadata(_session), do: nil

  defp maybe_put_map(map, _key, nil), do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, value)
end
