defmodule Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriverTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.AsmRuntimeBridge.{RuntimeControlDriver, SessionStore}
  alias Jido.Integration.V2.AsmRuntimeBridge.TestSupport.StreamScriptedDriver

  alias Jido.RuntimeControl.{
    ExecutionEvent,
    ExecutionResult,
    RunHandle,
    RunRequest,
    RuntimeDescriptor,
    SessionHandle
  }

  alias ASM.{Event, HostTool}
  alias Jido.Integration.V2.AsmRuntimeBridge.Normalizer

  setup do
    ensure_asm_runtime_bridge_started!()
    SessionStore.reset!()
    :ok
  end

  test "start_session/1 fails loudly when the runtime app is not started" do
    assert :ok = stop_asm_runtime_bridge!()
    assert Process.whereis(SessionStore) == nil

    assert_raise ArgumentError, ~r/asm_runtime_bridge session store is not started/, fn ->
      RuntimeControlDriver.start_session(provider: :claude)
    end
  end

  test "runtime_descriptor/1 reports provider-aware capabilities truthfully" do
    descriptor = RuntimeControlDriver.runtime_descriptor(provider: :claude)

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
    assert {:ok, session} = RuntimeControlDriver.start_session(provider: :claude)
    assert {:ok, session_ref} = SessionStore.fetch(session.session_id)

    refute Map.has_key?(Map.from_struct(session), :driver_ref)
    assert is_pid(session_ref)

    assert :ok = RuntimeControlDriver.stop_session(session)
    assert :error = SessionStore.fetch(session.session_id)
  end

  test "start_session/1 and session_status/1 carry wave-5 boundary metadata for session lanes" do
    assert {:ok, session} =
             RuntimeControlDriver.start_session(
               provider: :claude,
               workspace_root: "/tmp/runtime-boundary",
               target_id: "boundary-target-1",
               surface_ref: "surface-1",
               surface_kind: :ssh_exec,
               lease_ref: "lease-1",
               permission_mode: :plan,
               allowed_tools: ["test.session.exec"],
               context: %{route: %{route_id: "route-1"}, decision_id: "decision-1"}
             )

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    assert session.metadata["boundary"]["descriptor"]["boundary_session_id"] == session.session_id
    assert session.metadata["boundary"]["descriptor"]["decision_id"] == "decision-1"
    assert session.metadata["boundary"]["descriptor"]["workspace_ref"] == "/tmp/runtime-boundary"
    assert session.metadata["boundary"]["descriptor"]["lease_refs"] == ["lease-1"]
    assert session.metadata["boundary"]["route"]["route_id"] == "route-1"

    assert session.metadata["boundary"]["route"]["resolved_target"] == %{
             "surface_kind" => "ssh_exec",
             "surface_ref" => "surface-1",
             "target_id" => "boundary-target-1"
           }

    assert session.metadata["boundary"]["attach_grant"] == %{
             "attach_mode" => "read_only",
             "attach_surface" => %{
               "surface_kind" => "ssh_exec",
               "surface_ref" => "surface-1",
               "target_id" => "boundary-target-1"
             },
             "boundary_session_id" => session.session_id,
             "granted_capabilities" => ["test.session.exec"],
             "working_directory" => "/tmp/runtime-boundary"
           }

    assert {:ok, status} = RuntimeControlDriver.session_status(session)
    assert status.details["boundary"]["descriptor"]["session_status"] == "ready"
  end

  test "stream_run/3 maps asm envelopes to runtime-control execution events" do
    assert {:ok, session} = RuntimeControlDriver.start_session(provider: :claude)

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    request = RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:ok, run, stream} =
             RuntimeControlDriver.stream_run(session, request,
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

  test "stream_run/3 passes host tools and continuation into the ASM run" do
    assert {:ok, session} = RuntimeControlDriver.start_session(provider: :codex)

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    request =
      RunRequest.new!(%{
        prompt: "use echo_json",
        host_tools: [
          %{
            "name" => "echo_json",
            "inputSchema" => %{"type" => "object"}
          }
        ],
        continuation: %{
          strategy: :exact,
          provider_session_id: "codex-thread-1"
        },
        metadata: %{}
      })

    assert {:ok, _run, stream} =
             RuntimeControlDriver.stream_run(session, request,
               driver: StreamScriptedDriver,
               driver_opts: [test_pid: self()],
               app_server: true,
               tools: %{"echo_json" => fn args -> {:ok, args} end},
               run_id: "bridge-run-host-tools"
             )

    assert Enum.to_list(stream) != []

    assert_receive {:stream_scripted_driver_context, context}
    assert context.continuation == %{strategy: :exact, provider_session_id: "codex-thread-1"}
    assert Keyword.fetch!(context.provider_opts, :app_server) == true
    assert [%{"name" => "echo_json"}] = Keyword.fetch!(context.provider_opts, :host_tools)
    assert is_function(context.tools["echo_json"], 1)
  end

  test "start_session/1 and stream_run/3 do not forward caller-supplied env options" do
    assert {:ok, session} =
             RuntimeControlDriver.start_session(
               provider: :codex,
               env: %{"credential_token" => "must-not-cross"}
             )

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    assert {:ok, session_ref} = SessionStore.fetch(session.session_id)
    assert {:ok, info} = ASM.session_info(session_ref)
    refute inspect(Keyword.get(info.options, :env)) =~ "must-not-cross"

    request = RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:ok, _run, stream} =
             RuntimeControlDriver.stream_run(session, request,
               driver: StreamScriptedDriver,
               driver_opts: [test_pid: self()],
               env: %{"credential_token" => "must-not-cross"},
               run_id: "bridge-run-no-env"
             )

    assert Enum.to_list(stream) != []

    assert_receive {:stream_scripted_driver_context, context}
    refute inspect(Map.get(context, :env)) =~ "must-not-cross"
    refute inspect(Keyword.get(context.provider_opts, :env)) =~ "must-not-cross"
  end

  test "stream_run/3 rejects host tools for unsupported providers with a Jido-facing error" do
    assert {:ok, session} = RuntimeControlDriver.start_session(provider: :gemini)

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    request =
      RunRequest.new!(%{
        prompt: "use echo_json",
        host_tools: [%{"name" => "echo_json", "inputSchema" => %{"type" => "object"}}],
        metadata: %{}
      })

    assert {:error, error} =
             RuntimeControlDriver.stream_run(session, request,
               driver: StreamScriptedDriver,
               run_id: "bridge-run-host-tools-rejected"
             )

    assert Exception.message(error) =~ "host_tools"
    assert Exception.message(error) =~ "gemini"
  end

  test "normalizer projects host tool events and redacts raw provider evidence" do
    session =
      SessionHandle.new!(%{
        session_id: "session-1",
        runtime_id: :asm,
        provider: :codex,
        metadata: %{}
      })

    request =
      HostTool.Request.new!(
        id: "jsonrpc-1",
        session_id: "session-1",
        run_id: "run-1",
        provider: :codex,
        provider_session_id: "codex-thread-1",
        provider_turn_id: "codex-turn-1",
        tool_name: "echo_json",
        arguments: %{"access_token" => "secret-token"},
        raw: %{access_token: "secret-token"},
        metadata: %{call_id: "call-1"}
      )

    event =
      Event.new(:host_tool_requested, request,
        run_id: "run-1",
        session_id: "session-1",
        provider: :codex,
        provider_session_id: "codex-thread-1",
        metadata: %{
          provider_turn_id: "codex-turn-1",
          tool_name: "echo_json",
          call_id: "call-1",
          access_token: "secret-token"
        }
      )

    projected = Normalizer.to_execution_event(event, session)

    assert projected.type == :host_tool_requested
    assert projected.provider_session_id == "codex-thread-1"
    assert projected.provider_turn_id == "codex-turn-1"
    assert projected.provider_request_id == "jsonrpc-1"
    assert projected.provider_tool_call_id == "call-1"
    assert projected.tool_name == "echo_json"
    refute Map.has_key?(projected.payload, "raw")
    assert projected.payload["arguments"]["access_token"] == "[REDACTED]"
    assert projected.raw["metadata"]["access_token"] == "[REDACTED]"
  end

  test "run/3 maps asm results to runtime-control execution results" do
    assert {:ok, session} = RuntimeControlDriver.start_session(provider: :claude)

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    request = RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:ok, result} =
             RuntimeControlDriver.run(session, request,
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
    assert {:ok, session} = RuntimeControlDriver.start_session(provider: :claude)

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    request = RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:ok, result} =
             RuntimeControlDriver.run(session, request,
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

  test "start_session/1 authors execution_surface and execution_environment from context" do
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
             RuntimeControlDriver.start_session(
               provider: :claude,
               capability: %{id: "test.session.exec", runtime_class: :session},
               input: %{prompt: "hello"},
               context: context,
               surface_kind: :ssh_exec,
               surface_ref: "surface-1",
               boundary_class: :isolated,
               observability: %{suite: :phase_c},
               transport_options: %{destination: "bridge.runtime.example"}
             )

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    assert {:ok, session_ref} = SessionStore.fetch(session.session_id)
    assert {:ok, info} = ASM.session_info(session_ref)

    assert info.options[:execution_surface].surface_kind == :ssh_exec

    assert info.options[:execution_surface].transport_options == [
             destination: "bridge.runtime.example"
           ]

    assert info.options[:execution_surface].lease_ref == "lease-1"
    assert info.options[:execution_surface].surface_ref == "surface-1"
    assert info.options[:execution_surface].target_id == "target-1"
    assert info.options[:execution_surface].boundary_class == :isolated
    assert info.options[:execution_surface].observability == %{suite: :phase_c}
    assert info.options[:execution_environment].workspace_root == "/tmp/runtime"
    assert info.options[:execution_environment].allowed_tools == ["test.session.exec"]
    assert info.options[:execution_environment].approval_posture == :none
    assert info.options[:execution_environment].permission_mode == :bypass
  end

  test "stream_run/3 keeps request cwd separate from authored workspace_root" do
    assert {:ok, session} =
             RuntimeControlDriver.start_session(
               provider: :claude,
               workspace_root: "/tmp/runtime-root"
             )

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    request =
      RunRequest.new!(%{
        prompt: "hello",
        metadata: %{},
        cwd: "/tmp/request-cwd"
      })

    assert {:ok, _run, stream} =
             RuntimeControlDriver.stream_run(session, request,
               driver: StreamScriptedDriver,
               run_id: "bridge-run-cwd"
             )

    assert Enum.to_list(stream) != []

    assert {:ok, session_ref} = SessionStore.fetch(session.session_id)
    assert {:ok, info} = ASM.session_info(session_ref)
    assert info.options[:execution_environment].workspace_root == "/tmp/runtime-root"
  end

  test "reuse_key/4 keeps control-plane credential leases out of stable session identity" do
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
        execution_surface: [
          surface_kind: :ssh_exec,
          surface_ref: "surface-1"
        ]
      }
    }

    reuse_key = RuntimeControlDriver.reuse_key(capability, input, context, runtime_config)

    assert reuse_key.surface_kind == :ssh_exec
    assert reuse_key.lease_ref == nil
    assert reuse_key.surface_ref == "surface-1"
  end

  test "reuse_key/4 respects authored execution-surface overrides from runtime config" do
    capability = %{id: "cap-1", runtime_class: :session}
    input = %{prompt: "hello"}

    context = %{
      credential_ref: %{id: "cred-1"},
      credential_lease: %{lease_id: "lease-from-context"},
      target_descriptor: %{
        target_id: "target-from-context",
        location: %{workspace_root: "/tmp/runtime-context"}
      },
      policy_inputs: %{execution: %{sandbox: %{file_scope: "/tmp/runtime-context"}}}
    }

    runtime_config = %{
      provider: :claude,
      options: %{
        execution_surface: [
          surface_kind: :ssh_exec,
          lease_ref: "lease-from-runtime",
          surface_ref: "surface-from-runtime",
          target_id: "target-from-runtime"
        ],
        execution_environment: [
          workspace_root: "/tmp/runtime-override"
        ]
      }
    }

    reuse_key = RuntimeControlDriver.reuse_key(capability, input, context, runtime_config)

    assert reuse_key.workspace_root == "/tmp/runtime-override"
    assert reuse_key.lease_ref == "lease-from-runtime"
    assert reuse_key.surface_ref == "surface-from-runtime"
    assert reuse_key.target_id == "target-from-runtime"
  end

  defp stop_asm_runtime_bridge! do
    app = :jido_integration_v2_asm_runtime_bridge

    if pid = Process.whereis(Jido.Integration.V2.AsmRuntimeBridge.Application.Supervisor) do
      ref = Process.monitor(pid)
      :ok = Application.stop(app)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5_000 -> flunk("asm_runtime_bridge supervisor did not stop")
      end
    else
      :ok
    end
  end

  defp ensure_asm_runtime_bridge_started! do
    case Application.ensure_all_started(:jido_integration_v2_asm_runtime_bridge) do
      {:ok, _apps} -> :ok
      {:error, reason} -> flunk("failed to start asm_runtime_bridge: #{inspect(reason)}")
    end
  end
end
