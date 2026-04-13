defmodule Jido.Session.RuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.RuntimeControl.{
    ExecutionEvent,
    ExecutionResult,
    ExecutionStatus,
    RunHandle,
    RunRequest,
    SessionHandle
  }

  alias Jido.Session

  test "starts and stops sessions" do
    session_id = unique_id("session")

    assert {:ok, %SessionHandle{} = session} =
             Session.start_session(
               session_id: session_id,
               provider: :jido_session,
               cwd: "/tmp/project",
               metadata: %{"scope" => "unit"}
             )

    assert session.session_id == session_id
    assert session.runtime_id == :jido_session
    assert session.status == :ready
    refute Map.has_key?(Map.from_struct(session), :driver_ref)

    assert {:ok, internal_session} = Session.fetch_session(session_id)
    assert internal_session.session_id == session_id
    assert internal_session.cwd == "/tmp/project"
    assert internal_session.status == :ready
    assert internal_session.metadata["scope"] == "unit"

    assert {:ok, %ExecutionStatus{} = status} = Session.session_status(session)
    assert status.scope == :session
    assert status.state == :ready

    assert :ok = Session.stop_session(session)
    assert {:error, :not_found} = Session.fetch_session(session_id)
  end

  test "launches a run and projects normalized events" do
    session_id = unique_id("session")
    run_id = unique_id("run")
    request = RunRequest.new!(%{prompt: "fix login bug", metadata: %{"ticket" => "AUTH-12"}})

    assert {:ok, %SessionHandle{} = session} = Session.start_session(session_id: session_id)

    try do
      assert {:ok, %RunHandle{} = run, stream} =
               Session.stream_run(session, request, run_id: run_id)

      assert run.run_id == run_id
      assert run.session_id == session_id
      assert run.status == :running

      events = Enum.to_list(stream)

      assert Enum.all?(events, &match?(%ExecutionEvent{}, &1))
      assert Enum.map(events, & &1.type) == [:run_started, :assistant_message, :result]

      [started, message, result] = events

      assert started.payload["prompt"] == "fix login bug"
      assert started.status == :running

      assert message.payload["role"] == "assistant"
      assert message.payload["content"] == "handled: fix login bug"
      assert message.sequence == 2

      assert result.status == :completed
      assert result.payload["text"] == "handled: fix login bug"
      assert result.payload["message_count"] == 2

      assert {:ok, internal_run} = Session.fetch_run(run_id)
      assert internal_run.run_id == run_id
      assert internal_run.status == :completed
      assert internal_run.result_text == "handled: fix login bug"

      assert internal_run.messages == [
               %{"role" => "user", "content" => "fix login bug"},
               %{"role" => "assistant", "content" => "handled: fix login bug"}
             ]
    after
      _ = Session.stop_session(session)
    end
  end

  test "projects deterministic terminal results" do
    session_id = unique_id("session")
    run_id = unique_id("run")
    request = RunRequest.new!(%{prompt: "write docs", metadata: %{"suite" => "result"}})

    assert {:ok, %SessionHandle{} = session} =
             Session.start_session(
               session_id: session_id,
               provider: :jido_session,
               metadata: %{"session_type" => "local_echo"}
             )

    try do
      assert {:ok, %ExecutionResult{} = result} = Session.run(session, request, run_id: run_id)

      assert result.run_id == run_id
      assert result.session_id == session_id
      assert result.runtime_id == :jido_session
      assert result.status == :completed
      assert result.text == "handled: write docs"
      assert result.stop_reason == "completed"
      assert result.duration_ms == 0
      assert result.metadata["session_type"] == "local_echo"
      assert result.metadata["request_metadata"] == %{"suite" => "result"}

      assert result.messages == [
               %{"role" => "user", "content" => "write docs"},
               %{"role" => "assistant", "content" => "handled: write docs"}
             ]

      assert {:ok, internal_run} = Session.fetch_run(run_id)
      assert internal_run.status == :completed
      assert internal_run.result_text == "handled: write docs"
    after
      _ = Session.stop_session(session)
    end
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
