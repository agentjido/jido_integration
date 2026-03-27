defmodule Jido.Integration.V2.RuntimeAsmBridge.HarnessDriverTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.RuntimeAsmBridge.{HarnessDriver, SessionStore}
  alias Jido.Integration.V2.RuntimeAsmBridge.TestSupport.StreamScriptedDriver

  alias Jido.Harness.{
    ExecutionEvent,
    ExecutionResult,
    RunHandle,
    RunRequest,
    RuntimeDescriptor
  }

  setup do
    SessionStore.reset!()
    :ok
  end

  test "runtime_descriptor/1 reports provider-aware capabilities truthfully" do
    descriptor = HarnessDriver.runtime_descriptor(provider: :claude)

    assert %RuntimeDescriptor{} = descriptor
    assert descriptor.runtime_id == :asm
    assert descriptor.provider == :claude
    assert descriptor.streaming?
    assert descriptor.cancellation?
    assert descriptor.approvals?
    assert descriptor.cost?
    refute descriptor.resume?
    refute descriptor.subscribe?
  end

  test "start_session/1 keeps the asm pid private and keys the store by session_id" do
    assert {:ok, session} = HarnessDriver.start_session(provider: :claude)
    assert {:ok, session_ref} = SessionStore.fetch(session.session_id)

    refute Map.has_key?(Map.from_struct(session), :driver_ref)
    assert is_pid(session_ref)

    assert :ok = HarnessDriver.stop_session(session)
    assert :error = SessionStore.fetch(session.session_id)
  end

  test "stream_run/3 maps asm envelopes to harness execution events" do
    assert {:ok, session} = HarnessDriver.start_session(provider: :claude)

    on_exit(fn ->
      _ = HarnessDriver.stop_session(session)
    end)

    request = RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:ok, run, stream} =
             HarnessDriver.stream_run(session, request,
               driver: StreamScriptedDriver,
               run_id: "bridge-run-1"
             )

    assert %RunHandle{run_id: "bridge-run-1", runtime_id: :asm, provider: :claude} = run

    events = Enum.to_list(stream)

    assert [
             %ExecutionEvent{type: :run_started, provider: :claude},
             %ExecutionEvent{
               type: :assistant_delta,
               provider: :claude,
               payload: %{"content" => "hello ", "format" => "text"}
             },
             %ExecutionEvent{
               type: :assistant_delta,
               provider: :claude,
               payload: %{"content" => "from scripted driver", "format" => "text"}
             },
             %ExecutionEvent{type: :result, provider: :claude}
           ] = events
  end

  test "run/3 maps asm results to harness execution results" do
    assert {:ok, session} = HarnessDriver.start_session(provider: :claude)

    on_exit(fn ->
      _ = HarnessDriver.stop_session(session)
    end)

    request = RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:ok, result} =
             HarnessDriver.run(session, request,
               driver: StreamScriptedDriver,
               run_id: "bridge-run-2"
             )

    assert %ExecutionResult{} = result
    assert result.runtime_id == :asm
    assert result.provider == :claude
    assert result.run_id == "bridge-run-2"
    assert result.status == :completed
    assert result.text == "hello from scripted driver"
    assert result.stop_reason == "end_turn"
  end

  test "run/3 maps cancelled asm results to cancelled execution results" do
    assert {:ok, session} = HarnessDriver.start_session(provider: :claude)

    on_exit(fn ->
      _ = HarnessDriver.stop_session(session)
    end)

    request = RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:ok, result} =
             HarnessDriver.run(session, request,
               driver: StreamScriptedDriver,
               run_id: "bridge-run-3",
               driver_opts: [
                 script: [
                   {:assistant_delta,
                    %ASM.Message.Partial{content_type: :text, delta: "partial"}},
                   {:error,
                    %ASM.Message.Error{
                      severity: :warning,
                      message: "Run interrupted",
                      kind: :user_cancelled
                    }}
                 ]
               ]
             )

    assert %ExecutionResult{} = result
    assert result.run_id == "bridge-run-3"
    assert result.status == :cancelled
    assert result.error["kind"] == "user_cancelled"
    assert result.error["message"] == "Run interrupted"
  end

  test "start_session/1 authors generic execution-surface input from context" do
    context = %{
      run_id: "run-1",
      attempt_id: "run-1:1",
      credential_ref: %{id: "cred-1"},
      credential_lease: %{lease_id: "lease-1"},
      target_descriptor: %{
        target_id: "target-1",
        location: %{workspace_root: "/tmp/runtime"}
      },
      policy_inputs: %{
        execution: %{
          sandbox: %{
            approvals: :none,
            allowed_tools: ["test.session.exec"],
            file_scope: "/tmp/runtime"
          }
        }
      }
    }

    assert {:ok, session} =
             HarnessDriver.start_session(
               provider: :claude,
               capability: %{id: "test.session.exec", runtime_class: :session},
               input: %{prompt: "hello"},
               context: context,
               surface_kind: :leased_ssh,
               surface_ref: "surface-1",
               boundary_class: :isolated,
               observability: %{suite: :phase_c},
               transport_options: %{startup_mode: :lazy}
             )

    on_exit(fn ->
      _ = HarnessDriver.stop_session(session)
    end)

    assert {:ok, session_ref} = SessionStore.fetch(session.session_id)
    assert {:ok, info} = ASM.session_info(session_ref)

    assert info.options[:surface_kind] == :leased_ssh
    assert info.options[:transport_options] == [startup_mode: :lazy]
    assert info.options[:workspace_root] == "/tmp/runtime"
    assert info.options[:allowed_tools] == ["test.session.exec"]
    assert info.options[:approval_posture] == :none
    assert info.options[:lease_ref] == "lease-1"
    assert info.options[:surface_ref] == "surface-1"
    assert info.options[:target_id] == "target-1"
    assert info.options[:boundary_class] == :isolated
    assert info.options[:observability] == %{suite: :phase_c}
  end

  test "reuse_key/4 widens identity for ephemeral execution surfaces" do
    capability = %{id: "cap-1", runtime_class: :session}
    input = %{prompt: "hello"}

    context = %{
      credential_ref: %{id: "cred-1"},
      credential_lease: %{lease_id: "lease-1"},
      target_descriptor: %{
        target_id: "target-1",
        location: %{workspace_root: "/tmp/runtime"}
      },
      policy_inputs: %{execution: %{sandbox: %{file_scope: "/tmp/runtime"}}}
    }

    runtime_config = %{
      provider: :claude,
      options: %{
        surface_kind: :leased_ssh,
        surface_ref: "surface-1"
      }
    }

    reuse_key = HarnessDriver.reuse_key(capability, input, context, runtime_config)

    assert reuse_key.surface_kind == :leased_ssh
    assert reuse_key.lease_ref == "lease-1"
    assert reuse_key.surface_ref == "surface-1"
  end
end
