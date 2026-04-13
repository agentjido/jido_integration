defmodule Jido.RuntimeControl.Test.InvalidRuntimeDriverStub do
  @moduledoc false

  def runtime_id, do: :invalid_runtime
end

defmodule Jido.RuntimeControl.Test.RuntimeDriverStub do
  @moduledoc false
  @behaviour Jido.RuntimeControl.RuntimeDriver

  alias Jido.RuntimeControl.{
    ExecutionEvent,
    ExecutionResult,
    ExecutionStatus,
    RunHandle,
    RunRequest,
    RuntimeDescriptor,
    SessionHandle
  }

  def runtime_id, do: :stub_runtime

  def runtime_descriptor(opts \\ []) do
    provider = Keyword.get(opts, :provider, :stub_runtime)

    RuntimeDescriptor.new!(%{
      runtime_id: :stub_runtime,
      provider: provider,
      label: "Stub Runtime",
      session_mode: :external,
      streaming?: true,
      cancellation?: true,
      approvals?: true,
      cost?: true,
      subscribe?: false,
      resume?: false,
      metadata: %{"surface" => "stub"}
    })
  end

  def start_session(opts) when is_list(opts) do
    session_id = Keyword.get(opts, :session_id, "runtime-session-1")
    provider = Keyword.get(opts, :provider, :stub_runtime)
    send(self(), {:runtime_driver_stub_start_session, opts})

    {:ok,
     SessionHandle.new!(%{
       session_id: session_id,
       runtime_id: :stub_runtime,
       provider: provider,
       status: :ready,
       metadata: %{"started_via" => "stub"}
     })}
  end

  def stop_session(%SessionHandle{} = session) do
    send(self(), {:runtime_driver_stub_stop_session, session.session_id})
    :ok
  end

  def stream_run(%SessionHandle{} = session, %RunRequest{} = request, opts) do
    send(self(), {:runtime_driver_stub_stream_run, session.session_id, request, opts})
    run_id = Keyword.get(opts, :run_id, "runtime-run-1")

    run =
      RunHandle.new!(%{
        run_id: run_id,
        session_id: session.session_id,
        runtime_id: session.runtime_id,
        provider: session.provider,
        status: :running,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        metadata: %{"prompt" => request.prompt}
      })

    events = [
      ExecutionEvent.new!(%{
        event_id: "event-1",
        type: :run_started,
        session_id: session.session_id,
        run_id: run_id,
        runtime_id: session.runtime_id,
        provider: session.provider,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: :running,
        payload: %{"prompt" => request.prompt}
      }),
      ExecutionEvent.new!(%{
        event_id: "event-2",
        type: :result,
        session_id: session.session_id,
        run_id: run_id,
        runtime_id: session.runtime_id,
        provider: session.provider,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: :completed,
        payload: %{"text" => "stub result"}
      })
    ]

    {:ok, run, events}
  end

  def run(%SessionHandle{} = session, %RunRequest{} = request, opts) do
    send(self(), {:runtime_driver_stub_run, session.session_id, request, opts})
    run_id = Keyword.get(opts, :run_id, "runtime-run-1")

    {:ok,
     ExecutionResult.new!(%{
       run_id: run_id,
       session_id: session.session_id,
       runtime_id: session.runtime_id,
       provider: session.provider,
       status: :completed,
       text: "stub result",
       messages: [%{"role" => "assistant", "content" => request.prompt}],
       cost: %{"input_tokens" => 1, "output_tokens" => 1, "cost_usd" => 0.01},
       stop_reason: "end_turn",
       metadata: %{"prompt" => request.prompt}
     })}
  end

  def cancel_run(%SessionHandle{} = session, %RunHandle{} = run) do
    send(self(), {:runtime_driver_stub_cancel_run, session.session_id, run.run_id})
    :ok
  end

  def cancel_run(%SessionHandle{} = session, run_id) when is_binary(run_id) do
    send(self(), {:runtime_driver_stub_cancel_run, session.session_id, run_id})
    :ok
  end

  def session_status(%SessionHandle{} = session) do
    {:ok,
     ExecutionStatus.new!(%{
       runtime_id: session.runtime_id,
       session_id: session.session_id,
       scope: :session,
       state: session.status,
       timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
       details: %{"runtime_id" => Atom.to_string(session.runtime_id)}
     })}
  end

  def approve(%SessionHandle{} = session, approval_id, decision, opts) do
    send(self(), {:runtime_driver_stub_approve, session.session_id, approval_id, decision, opts})
    :ok
  end

  def cost(%SessionHandle{} = session) do
    send(self(), {:runtime_driver_stub_cost, session.session_id})
    {:ok, %{"input_tokens" => 1, "output_tokens" => 1, "cost_usd" => 0.01}}
  end
end

defmodule Jido.RuntimeControl.Test.AlphaRuntimeDriverStub do
  @moduledoc false
  @behaviour Jido.RuntimeControl.RuntimeDriver

  alias Jido.RuntimeControl.{
    ExecutionEvent,
    ExecutionResult,
    ExecutionStatus,
    RunHandle,
    RunRequest,
    RuntimeDescriptor,
    SessionHandle
  }

  def runtime_id, do: :alpha_runtime

  def runtime_descriptor(_opts \\ []) do
    RuntimeDescriptor.new!(%{
      runtime_id: :alpha_runtime,
      provider: :alpha_runtime,
      label: "Alpha Runtime",
      session_mode: :external,
      streaming?: true,
      cancellation?: true,
      approvals?: false,
      cost?: false,
      subscribe?: false,
      resume?: false,
      metadata: %{}
    })
  end

  def start_session(opts) do
    {:ok,
     SessionHandle.new!(%{
       session_id: Keyword.get(opts, :session_id, "alpha-session-1"),
       runtime_id: :alpha_runtime,
       provider: :alpha_runtime,
       status: :ready,
       metadata: %{}
     })}
  end

  def stop_session(_session), do: :ok

  def stream_run(%SessionHandle{} = session, %RunRequest{} = request, opts) do
    run =
      RunHandle.new!(%{
        run_id: Keyword.get(opts, :run_id, "alpha-run-1"),
        session_id: session.session_id,
        runtime_id: session.runtime_id,
        provider: session.provider,
        status: :running,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        metadata: %{}
      })

    events = [
      ExecutionEvent.new!(%{
        event_id: "alpha-event-1",
        type: :run_started,
        session_id: session.session_id,
        run_id: run.run_id,
        runtime_id: session.runtime_id,
        provider: session.provider,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: :running,
        payload: %{"prompt" => request.prompt}
      })
    ]

    {:ok, run, events}
  end

  def cancel_run(_session, _run), do: :ok

  def session_status(%SessionHandle{} = session) do
    {:ok,
     ExecutionStatus.new!(%{
       runtime_id: session.runtime_id,
       session_id: session.session_id,
       scope: :session,
       state: :ready,
       timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
       details: %{}
     })}
  end

  def run(%SessionHandle{} = session, %RunRequest{} = request, opts) do
    {:ok,
     ExecutionResult.new!(%{
       run_id: Keyword.get(opts, :run_id, "alpha-run-1"),
       session_id: session.session_id,
       runtime_id: session.runtime_id,
       provider: session.provider,
       status: :completed,
       text: request.prompt,
       messages: [],
       cost: %{},
       stop_reason: "completed",
       metadata: %{}
     })}
  end
end
