defmodule Jido.Session.RuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Harness.{
    ExecutionEvent,
    ExecutionResult,
    ExecutionStatus,
    RunHandle,
    RunRequest,
    SessionHandle
  }

  alias Jido.Session
  alias Jido.Session.TestSupport.BoundaryTestAdapter

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

  test "allocates a boundary-backed jido_session lane through the shared bridge seam" do
    store = start_supervised!(BoundaryTestAdapter)

    request =
      RunRequest.new!(%{
        prompt: "review packet",
        metadata: %{"suite" => "boundary"}
      })

    assert {:ok, %SessionHandle{} = session} =
             Session.start_session(
               session_id: "boundary-session-1",
               provider: :jido_session,
               boundary_request: %{
                 boundary_session_id: "bnd-jido-session-1",
                 backend_kind: :microvm,
                 boundary_class: :leased_cell,
                 attach: %{mode: :not_applicable, working_directory: "/srv/jido-session"},
                 policy_intent: %{
                   sandbox_level: :strict,
                   egress: :restricted,
                   approvals: :manual,
                   allowed_tools: ["git.status"],
                   file_scope: "/srv/jido-session"
                 },
                 refs: %{
                   target_id: "target-jido-session-1",
                   runtime_ref: "runtime-jido-session-1",
                   correlation_id: "corr-jido-session-1",
                   request_id: "req-jido-session-1"
                 },
                 allocation_ttl_ms: 250
               },
               boundary_adapter: BoundaryTestAdapter,
               boundary_adapter_opts: [store: store]
             )

    try do
      assert session.metadata["boundary"]["descriptor"]["descriptor_version"] == 1

      assert session.metadata["boundary"]["descriptor"]["boundary_session_id"] ==
               "bnd-jido-session-1"

      assert {:ok, internal_session} = Session.fetch_session("boundary-session-1")
      assert internal_session.cwd == "/srv/jido-session"

      assert internal_session.metadata["boundary"]["descriptor"]["boundary_session_id"] ==
               "bnd-jido-session-1"

      assert {:ok, %ExecutionResult{} = result} =
               Session.run(session, request, run_id: "boundary-run-1")

      assert result.metadata["boundary"]["descriptor"]["descriptor_version"] == 1

      assert result.metadata["boundary"]["descriptor"]["attach"]["mode"] == "not_applicable"
    after
      _ = Session.stop_session(session)
    end
  end

  test "fails closed on an unsupported boundary descriptor_version" do
    store = start_supervised!(BoundaryTestAdapter)

    BoundaryTestAdapter.put_descriptor(store, "bnd-jido-session-unsupported", %{
      descriptor_version: 2,
      boundary_session_id: "bnd-jido-session-unsupported",
      backend_kind: :microvm,
      boundary_class: :leased_cell,
      status: :running,
      attach_ready?: false,
      workspace: %{
        workspace_root: "/srv/jido-session-unsupported",
        snapshot_ref: nil,
        artifact_namespace: "req-jido-session-unsupported"
      },
      attach: %{
        mode: :not_applicable,
        execution_surface: nil,
        working_directory: "/srv/jido-session-unsupported"
      },
      checkpointing: %{supported?: false, last_checkpoint_id: nil},
      policy_intent_echo: %{},
      refs: %{
        target_id: "target-jido-session-unsupported",
        runtime_ref: "runtime-jido-session-unsupported",
        correlation_id: "corr-jido-session-unsupported",
        request_id: "req-jido-session-unsupported"
      },
      extensions: %{},
      metadata: %{}
    })

    assert {:error, error} =
             Session.start_session(
               session_id: "boundary-session-unsupported",
               provider: :jido_session,
               boundary_request: %{
                 boundary_session_id: "bnd-jido-session-unsupported",
                 backend_kind: :microvm,
                 boundary_class: :leased_cell,
                 attach: %{
                   mode: :not_applicable,
                   working_directory: "/srv/jido-session-unsupported"
                 },
                 policy_intent: %{sandbox_level: :strict},
                 refs: %{
                   target_id: "target-jido-session-unsupported",
                   runtime_ref: "runtime-jido-session-unsupported",
                   correlation_id: "corr-jido-session-unsupported",
                   request_id: "req-jido-session-unsupported"
                 },
                 allocation_ttl_ms: 250
               },
               boundary_adapter: BoundaryTestAdapter,
               boundary_adapter_opts: [store: store]
             )

    assert Exception.message(error) =~ "descriptor_version"
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
