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
  alias Jido.Integration.V2.AsmRuntimeBridge.TestSupport.GovernedCodexBackend
  alias Jido.Integration.V2.{AuthSpec, CatalogSpec, Manifest, OperationSpec}

  setup do
    ensure_asm_runtime_bridge_started!()
    SessionStore.reset!()
    saved_codex_env = capture_codex_env()
    clear_codex_env()

    on_exit(fn -> restore_codex_env(saved_codex_env) end)

    :ok
  end

  test "start_session/1 fails loudly when the runtime app is not started" do
    assert :ok = stop_asm_runtime_bridge!()
    assert Process.whereis(SessionStore) == nil

    assert_raise ArgumentError, fn ->
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

  test "stream_run/3 maps governed dynamic tool manifests into ASM host tools" do
    assert {:ok, session} = RuntimeControlDriver.start_session(provider: :codex)

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    request = RunRequest.new!(%{prompt: "use linear graph", metadata: %{}})

    assert {:ok, _run, stream} =
             RuntimeControlDriver.stream_run(session, request,
               driver: StreamScriptedDriver,
               driver_opts: [test_pid: self()],
               app_server: true,
               dynamic_tool_manifest: %{tools: ["linear_graphql"]},
               connector_manifests: [
                 dynamic_tool_manifest_fixture("linear", "linear.graphql.execute")
               ],
               allowed_operations: ["linear.graphql.execute"],
               allowed_tools: ["linear.api.graphql.execute"],
               authority_ref: "authority://phase11",
               tenant_ref: "tenant://phase11",
               installation_ref: "installation://phase11",
               run_id: "bridge-run-dynamic-tools"
             )

    assert Enum.to_list(stream) != []

    assert_receive {:stream_scripted_driver_context, context}

    assert [%{"name" => "linear_graphql"} = tool] =
             Keyword.fetch!(context.provider_opts, :host_tools)

    assert get_in(tool, ["metadata", "operation_id"]) == "linear.graphql.execute"
    assert context.metadata["dynamic_tool_manifest"]["operations"] == ["linear.graphql.execute"]
    assert context.metadata["dynamic_tool_manifest"]["authority_ref"] == "authority://phase11"
  end

  test "stream_run/3 rejects dynamic tool manifests outside Citadel allowed operations" do
    assert {:ok, session} = RuntimeControlDriver.start_session(provider: :codex)

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    request = RunRequest.new!(%{prompt: "use linear graph", metadata: %{}})

    assert {:error, error} =
             RuntimeControlDriver.stream_run(session, request,
               driver: StreamScriptedDriver,
               app_server: true,
               dynamic_tool_manifest: %{tools: ["linear_graphql"]},
               connector_manifests: [
                 dynamic_tool_manifest_fixture("linear", "linear.graphql.execute")
               ],
               allowed_operations: ["github.pr.create"],
               allowed_tools: ["linear.api.graphql.execute"],
               run_id: "bridge-run-dynamic-tools-rejected"
             )

    assert String.contains?(error.message, "ASM bridge stream_run/3 failed")
    assert String.contains?(error.details.error, "not present in Citadel allowed_operations")
  end

  test "stream_run/3 carries governed Codex evidence into ASM strict materialization" do
    assert {:ok, session} =
             RuntimeControlDriver.start_session(governed_codex_session_opts())

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    request =
      RunRequest.new!(%{
        prompt: "phase 10 deterministic codex",
        metadata: %{}
      })

    assert {:ok, _run, stream} =
             RuntimeControlDriver.stream_run(session, request,
               lane: :core,
               backend_module: GovernedCodexBackend,
               codex_materialized_runtime: materialized_runtime(),
               backend_opts: [test_pid: self()],
               run_id: "bridge-governed-codex-run"
             )

    events = Enum.to_list(stream)
    assert Enum.any?(events, &(&1.type == :assistant_delta))
    assert Enum.any?(events, &(&1.type == :result))

    metadata = events |> List.last() |> Map.fetch!(:raw) |> Map.fetch!("metadata")
    assert metadata["runtime_auth_mode"] == "governed"
    assert metadata["codex_materialization"]["command"] == "redacted_materialized_command"
    assert metadata["codex_materialization"]["credential_lease_ref"] == "[REDACTED]"
    assert metadata["codex_materialization"]["env_keys"] == ["CODEX_HOME"]

    refute String.contains?(inspect(events), "/materialized/bin/codex")
    refute String.contains?(inspect(events), "/materialized/phase10/workspace")
    refute String.contains?(inspect(events), "/materialized/phase10/codex-home")
    refute String.contains?(inspect(events), "phase10-secret")

    assert_receive {:governed_codex_backend_cleanup, cleanup}
    assert cleanup.cleanup_status == :completed
    assert cleanup.materialized_command == :redacted_materialized_command
    assert cleanup.credential_lease_ref == "jido-credential-lease://phase10/lease-1"
    assert cleanup.env_keys == ["CODEX_HOME"]
    refute String.contains?(inspect(cleanup), "/materialized")
  end

  test "governed Codex bridge rejects provider-only calls without authority evidence" do
    assert {:error, error} =
             RuntimeControlDriver.start_session(
               provider: :codex,
               runtime_auth_mode: :governed,
               runtime_auth_scope: :governed
             )

    assert error.kind == :config_invalid

    assert String.contains?(
             error.message,
             "governed runtime_auth requires governed context source"
           )
  end

  test "governed Codex bridge rejects ambient auth before deterministic provider launch" do
    saved = capture_codex_env()
    System.put_env("CODEX_API_KEY", "ambient-phase10-secret")

    on_exit(fn -> restore_codex_env(saved) end)

    assert {:ok, session} =
             RuntimeControlDriver.start_session(governed_codex_session_opts())

    on_exit(fn ->
      _ = RuntimeControlDriver.stop_session(session)
    end)

    request =
      RunRequest.new!(%{
        prompt: "phase 10 deterministic codex",
        metadata: %{}
      })

    assert {:ok, _run, stream} =
             RuntimeControlDriver.stream_run(session, request,
               lane: :core,
               backend_module: GovernedCodexBackend,
               codex_materialized_runtime: materialized_runtime(),
               backend_opts: [test_pid: self()],
               run_id: "bridge-governed-codex-ambient-reject"
             )

    assert_raise ASM.Error, fn -> Enum.to_list(stream) end

    refute_receive {:governed_codex_backend_cleanup, _cleanup}
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
    refute String.contains?(inspect(Keyword.get(info.options, :env)), "must-not-cross")

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
    refute String.contains?(inspect(Map.get(context, :env)), "must-not-cross")
    refute String.contains?(inspect(Keyword.get(context.provider_opts, :env)), "must-not-cross")
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

    assert String.contains?(Exception.message(error), "host_tools")
    assert String.contains?(Exception.message(error), "gemini")
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

  defp governed_codex_session_opts do
    [
      provider: :codex,
      runtime_auth_mode: :governed,
      runtime_auth_scope: :governed,
      execution_context_ref: "asm-execution-context://phase10/governed",
      connector_instance_ref: "jido-connector-instance://phase10/codex-1",
      connector_binding_ref: "jido-connector-binding://phase10/codex-1",
      connector_id: "codex-cli-phase10",
      provider_account_ref: "provider-account://codex/phase10/redacted",
      provider_account_status: :known,
      authority_ref: "citadel-authority://phase10/decision-1",
      authority_decision_ref: "citadel-authority-decision://phase10/decision-1",
      credential_lease_ref: "jido-credential-lease://phase10/lease-1",
      native_auth_assertion_ref: "codex-native-auth://phase10/assertion-1",
      tenant_ref: "tenant://phase10",
      installation_ref: "installation://phase10",
      target_ref: "target://phase10/local",
      operation_policy_ref: "operation-policy://phase10/codex/session-turn",
      workspace_root: "workspace://phase10/opaque",
      approval_posture: :manual,
      allowed_tools: ["codex.session.turn"]
    ]
  end

  defp materialized_runtime do
    %{
      source: :verified_materializer,
      command: "/materialized/bin/codex",
      cwd: "/materialized/phase10/workspace",
      config_root: "/materialized/phase10/codex-home",
      env: %{"CODEX_HOME" => "/materialized/phase10/codex-home"},
      clear_env?: true,
      target_auth_posture: :materialize_on_attach,
      native_auth_assertion: %{
        introspection_level: :auth_file_metadata,
        limits: %{secrets: :redacted, token_values: :not_read},
        redacted?: true
      }
    }
  end

  defp capture_codex_env do
    Map.new(codex_env_keys(), &{&1, System.get_env(&1)})
  end

  defp clear_codex_env do
    Enum.each(codex_env_keys(), &System.delete_env/1)
  end

  defp restore_codex_env(saved) do
    Enum.each(saved, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)
  end

  defp codex_env_keys do
    ["CODEX_API_KEY", "OPENAI_API_KEY", "CODEX_HOME", "OPENAI_BASE_URL"]
  end

  defp dynamic_tool_manifest_fixture(connector, operation_id) do
    Manifest.new!(%{
      connector: connector,
      auth:
        AuthSpec.new!(%{
          binding_kind: :connection_id,
          auth_type: :oauth2,
          install: %{required: true},
          reauth: %{supported: true},
          requested_scopes: ["write"],
          lease_fields: ["access_token"],
          secret_names: []
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: connector,
          description: "#{connector} connector",
          category: "developer_tools",
          tags: [connector],
          docs_refs: [],
          maturity: :beta,
          publication: :public
        }),
      operations: [dynamic_tool_operation(operation_id)],
      triggers: [],
      runtime_families: [:direct]
    })
  end

  defp dynamic_tool_operation(operation_id) do
    OperationSpec.new!(%{
      operation_id: operation_id,
      name: String.replace(operation_id, ".", "_"),
      display_name: operation_id,
      description: "Executes #{operation_id}",
      runtime_class: :direct,
      transport_mode: :sdk,
      handler: __MODULE__,
      input_schema: Zoi.object(%{input: Zoi.string()}),
      output_schema: Zoi.object(%{ok: Zoi.boolean()}),
      permissions: %{required_scopes: ["write"]},
      policy: %{
        environment: %{allowed: [:prod]},
        sandbox: %{
          level: :standard,
          egress: :restricted,
          approvals: :auto,
          allowed_tools: [String.replace(operation_id, "linear.", "linear.api.")]
        }
      },
      upstream: %{method: "POST", path: "/"},
      consumer_surface: %{mode: :connector_local, reason: "test"},
      schema_policy: %{input: :defined, output: :defined},
      jido: %{}
    })
  end
end
