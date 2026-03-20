defmodule Jido.Integration.V2.ControlPlaneTest do
  use ExUnit.Case

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.HarnessRuntime
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver
  alias Jido.Integration.V2.TargetDescriptor
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  defmodule PassthroughAction do
    use Jido.Action,
      name: "passthrough_action",
      schema: [value: [type: :string, required: true]]

    @impl true
    def run(params, _context), do: {:ok, %{value: params.value}}
  end

  defmodule TestConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "test",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :api_token,
            install: %{required: true},
            reauth: %{supported: false},
            requested_scopes: ["echo:write"],
            lease_fields: ["access_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Test",
            description: "Control plane direct test connector",
            category: "test",
            tags: ["control_plane"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [
          OperationSpec.new!(%{
            operation_id: "test.echo",
            name: "echo",
            display_name: "Echo",
            description: "Echoes the provided value",
            runtime_class: :direct,
            transport_mode: :action,
            handler: PassthroughAction,
            input_schema: Zoi.map(description: "Echo input"),
            output_schema: Zoi.map(description: "Echo output"),
            permissions: %{required_scopes: ["echo:write"]},
            policy: %{
              allowed_actor_ids: ["control-plane-test"],
              allowed_tenant_ids: ["tenant-1"],
              allowed_environments: [:prod],
              allowed_runtime_classes: [:direct],
              sandbox: %{
                level: :strict,
                egress: :restricted,
                approvals: :auto,
                file_scope: "/srv/tenant-1",
                allowed_tools: ["connector.echo"]
              }
            },
            upstream: %{transport: :action},
            consumer_surface: %{
              mode: :connector_local,
              reason: "Control-plane proof connectors stay connector-local"
            },
            schema_policy: %{
              input: :passthrough,
              output: :passthrough,
              justification:
                "Control-plane test operations are internal proofs and do not participate in the normalized common consumer surface"
            },
            jido: %{action: %{name: "test_echo"}}
          })
        ],
        triggers: [],
        runtime_families: [:direct]
      })
    end
  end

  defmodule JidoSessionConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "jido_session_test",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :api_token,
            install: %{required: true},
            reauth: %{supported: false},
            requested_scopes: ["session:execute"],
            lease_fields: ["access_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Jido Session Test",
            description: "Control plane session test connector",
            category: "test",
            tags: ["session"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [
          OperationSpec.new!(%{
            operation_id: "test.session.prompt",
            name: "session_prompt",
            display_name: "Session prompt",
            description: "Prompts a session runtime",
            runtime_class: :session,
            transport_mode: :stdio,
            handler: PassthroughAction,
            input_schema: Zoi.map(description: "Session input"),
            output_schema: Zoi.map(description: "Session output"),
            permissions: %{required_scopes: ["session:execute"]},
            runtime: %{
              driver: "jido_session"
            },
            policy: %{
              allowed_actor_ids: ["control-plane-test"],
              allowed_tenant_ids: ["tenant-1"],
              allowed_environments: [:prod],
              allowed_runtime_classes: [:session],
              sandbox: %{
                level: :strict,
                egress: :restricted,
                approvals: :manual,
                file_scope: "/srv/tenant-1/session",
                allowed_tools: ["test.session.prompt"]
              }
            },
            upstream: %{transport: :stdio},
            consumer_surface: %{
              mode: :connector_local,
              reason: "Control-plane proof connectors stay connector-local"
            },
            schema_policy: %{
              input: :passthrough,
              output: :passthrough,
              justification:
                "Control-plane test operations are internal proofs and do not participate in the normalized common consumer surface"
            },
            jido: %{action: %{name: "test_session_prompt"}}
          })
        ],
        triggers: [],
        runtime_families: [:session]
      })
    end
  end

  defmodule AsmStreamConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "asm_stream_test",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :api_token,
            install: %{required: true},
            reauth: %{supported: false},
            requested_scopes: ["stream:execute"],
            lease_fields: ["access_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "ASM Stream Test",
            description: "Control plane stream test connector",
            category: "test",
            tags: ["stream"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [
          OperationSpec.new!(%{
            operation_id: "test.asm.stream",
            name: "asm_stream",
            display_name: "ASM stream",
            description: "Streams through ASM",
            runtime_class: :stream,
            transport_mode: :stdio,
            handler: PassthroughAction,
            input_schema: Zoi.map(description: "Stream input"),
            output_schema: Zoi.map(description: "Stream output"),
            permissions: %{required_scopes: ["stream:execute"]},
            runtime: %{
              driver: "asm",
              provider: :claude,
              options: %{
                driver: Jido.Integration.V2.ControlPlaneTest.AsmScriptedDriver
              }
            },
            policy: %{
              allowed_actor_ids: ["control-plane-test"],
              allowed_tenant_ids: ["tenant-1"],
              allowed_environments: [:prod],
              allowed_runtime_classes: [:stream],
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                file_scope: "/srv/tenant-1/asm",
                allowed_tools: ["test.asm.stream"]
              }
            },
            upstream: %{transport: :stdio},
            consumer_surface: %{
              mode: :connector_local,
              reason: "Control-plane proof connectors stay connector-local"
            },
            schema_policy: %{
              input: :passthrough,
              output: :passthrough,
              justification:
                "Control-plane test operations are internal proofs and do not participate in the normalized common consumer surface"
            },
            jido: %{action: %{name: "test_asm_stream"}}
          })
        ],
        triggers: [],
        runtime_families: [:stream]
      })
    end
  end

  defmodule AsmScriptedDriver do
    @moduledoc false

    alias ASM.Event
    alias ASM.Message
    alias ASM.Run

    @spec start(map()) :: {:ok, pid()}
    def start(%{} = context) do
      {:ok, spawn(fn -> emit(context) end)}
    end

    defp emit(context) do
      for {kind, payload} <- script() do
        Run.Server.ingest_event(
          context.run_pid,
          %Event{
            id: Event.generate_id(),
            kind: kind,
            run_id: context.run_id,
            session_id: context.session_id,
            provider: context.provider,
            payload: payload,
            timestamp: DateTime.utc_now()
          }
        )
      end
    end

    defp script do
      [
        {:assistant_delta, %Message.Partial{content_type: :text, delta: "hello "}},
        {:assistant_delta, %Message.Partial{content_type: :text, delta: "from control plane"}},
        {:result, %Message.Result{stop_reason: :end_turn}}
      ]
    end
  end

  defmodule LeakyAction do
    use Jido.Action,
      name: "leaky_action",
      schema: [value: [type: :string, required: true]]

    @impl true
    def run(params, context) do
      {:ok,
       %{
         value: params.value,
         credential_lease: context.credential_lease,
         echoed_secret: context.credential_lease.payload.access_token
       }}
    end
  end

  defmodule LeakyConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "leaky",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :api_token,
            install: %{required: true},
            reauth: %{supported: false},
            requested_scopes: ["echo:write"],
            lease_fields: ["access_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Leaky",
            description: "Control plane redaction test connector",
            category: "test",
            tags: ["redaction"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [
          OperationSpec.new!(%{
            operation_id: "leaky.echo",
            name: "leaky_echo",
            display_name: "Leaky echo",
            description: "Echoes through a leaky action",
            runtime_class: :direct,
            transport_mode: :action,
            handler: LeakyAction,
            input_schema: Zoi.map(description: "Leaky input"),
            output_schema: Zoi.map(description: "Leaky output"),
            permissions: %{required_scopes: ["echo:write"]},
            policy: %{
              allowed_actor_ids: ["control-plane-test"],
              allowed_tenant_ids: ["tenant-1"],
              allowed_environments: [:prod],
              allowed_runtime_classes: [:direct],
              sandbox: %{
                level: :strict,
                egress: :restricted,
                approvals: :auto,
                file_scope: "/srv/tenant-1",
                allowed_tools: ["connector.echo"]
              }
            },
            upstream: %{transport: :action},
            consumer_surface: %{
              mode: :connector_local,
              reason: "Control-plane proof connectors stay connector-local"
            },
            schema_policy: %{
              input: :passthrough,
              output: :passthrough,
              justification:
                "Control-plane test operations are internal proofs and do not participate in the normalized common consumer surface"
            },
            jido: %{action: %{name: "leaky_echo"}}
          })
        ],
        triggers: [],
        runtime_families: [:direct]
      })
    end
  end

  setup do
    ControlPlane.reset!()
    :ok
  end

  test "asm resolves to the target Harness runtime driver" do
    assert {:ok, HarnessDriver} = HarnessRuntime.driver_module("asm")
  end

  test "lists connectors deterministically and fetches connectors and capabilities by id" do
    assert :ok = ControlPlane.register_connector(TestConnector)
    assert :ok = ControlPlane.register_connector(LeakyConnector)

    assert [%Manifest{connector: "leaky"}, %Manifest{connector: "test"}] =
             ControlPlane.connectors()

    assert {:ok, %Manifest{connector: "test"} = manifest} = ControlPlane.fetch_connector("test")
    assert Enum.map(manifest.capabilities, & &1.id) == ["test.echo"]
    assert {:error, :unknown_connector} = ControlPlane.fetch_connector("missing")

    assert {:ok, %Capability{id: "leaky.echo", connector: "leaky"}} =
             ControlPlane.fetch_capability("leaky.echo")

    assert {:error, :unknown_capability} = ControlPlane.fetch_capability("missing.echo")
  end

  test "registers a manifest and records a completed run" do
    connection_id = install_connection!("tester", ["echo:write"], %{access_token: "test"})
    assert :ok = ControlPlane.register_connector(TestConnector)
    assert [%Capability{id: "test.echo"}] = ControlPlane.capabilities()

    assert {:ok, result} =
             ControlPlane.invoke("test.echo", %{value: "ok"}, invoke_opts(connection_id))

    assert result.run.status == :completed
    assert result.output == %{value: "ok"}
    assert result.attempt.attempt == 1
    assert result.attempt.attempt_id == "#{result.run.run_id}:1"
    assert String.starts_with?(result.attempt.credential_lease_id, "lease-")
    assert {:ok, stored_attempt} = ControlPlane.fetch_attempt(result.attempt.attempt_id)
    assert stored_attempt.attempt_id == result.attempt.attempt_id

    assert [
             %Event{attempt: 1, seq: 0, type: "run.started"},
             %Event{attempt: 1, seq: 1, type: "attempt.started"},
             %Event{attempt: 1, seq: 2, type: "attempt.completed"},
             %Event{attempt: 1, seq: 3, type: "run.completed"}
           ] = events = ControlPlane.events(result.run.run_id)

    assert Enum.all?(events, &(&1.attempt_id == result.attempt.attempt_id))
  end

  test "uses capability sandbox defaults when invoke opts omit sandbox" do
    connection_id = install_connection!("tester", ["echo:write"], %{access_token: "test"})
    assert :ok = ControlPlane.register_connector(TestConnector)

    assert {:ok, result} =
             ControlPlane.invoke(
               "test.echo",
               %{value: "ok"},
               Keyword.drop(invoke_opts(connection_id), [:sandbox])
             )

    assert result.run.status == :completed
    assert result.output == %{value: "ok"}
  end

  test "merges partial sandbox overrides with the capability policy contract" do
    connection_id = install_connection!("tester", ["echo:write"], %{access_token: "test"})
    assert :ok = ControlPlane.register_connector(TestConnector)

    assert {:ok, result} =
             ControlPlane.invoke(
               "test.echo",
               %{value: "ok"},
               invoke_opts(connection_id,
                 sandbox: %{
                   allowed_tools: ["connector.echo", "connector.debug"]
                 }
               )
             )

    assert result.run.status == :completed
    assert result.output == %{value: "ok"}
  end

  test "persists an explicit target selection through run, attempt, and event truth" do
    connection_id = install_connection!("tester", ["echo:write"], %{access_token: "test"})
    assert :ok = ControlPlane.register_connector(TestConnector)
    assert :ok = ControlPlane.announce_target(echo_target("target-echo"))

    assert {:ok, result} =
             ControlPlane.invoke(
               "test.echo",
               %{value: "ok"},
               invoke_opts(connection_id, target_id: "target-echo")
             )

    assert result.run.target_id == "target-echo"
    assert result.attempt.target_id == "target-echo"

    assert Enum.all?(ControlPlane.events(result.run.run_id), fn event ->
             event.target_id == "target-echo"
           end)
  end

  test "requires connection_id for capabilities with durable auth scopes" do
    assert :ok = ControlPlane.register_connector(TestConnector)

    assert {:error, :connection_required} =
             ControlPlane.invoke(
               "test.echo",
               %{value: "ok"},
               Keyword.drop(invoke_opts("connection-unused"), [:connection_id])
             )
  end

  test "fails before attempt creation when the selected target is incompatible" do
    connection_id = install_connection!("tester", ["echo:write"], %{access_token: "test"})
    assert :ok = ControlPlane.register_connector(TestConnector)

    assert :ok =
             ControlPlane.announce_target(echo_target("target-stream", runtime_class: :stream))

    assert {:error, error} =
             ControlPlane.invoke(
               "test.echo",
               %{value: "nope"},
               invoke_opts(connection_id, target_id: "target-stream")
             )

    assert error.reason == {:target_incompatible, "target-stream", :runtime_class_mismatch}
    assert error.run.status == :failed
    assert error.run.target_id == "target-stream"
    assert error.attempt == nil
    assert [%Event{attempt: nil, type: "run.failed"}] = ControlPlane.events(error.run.run_id)
  end

  test "fails before attempt creation when the selected session target advertises the wrong Harness driver" do
    connection_id = install_connection!("tester", ["session:execute"], %{access_token: "test"})
    assert :ok = ControlPlane.register_connector(JidoSessionConnector)

    assert :ok =
             ControlPlane.announce_target(
               harness_target("target-asm-session", "test.session.prompt", :session, "asm")
             )

    assert {:error, error} =
             ControlPlane.invoke(
               "test.session.prompt",
               %{prompt: "Draft a review packet"},
               invoke_opts(
                 connection_id,
                 allowed_operations: ["test.session.prompt"],
                 sandbox: %{
                   level: :strict,
                   egress: :restricted,
                   approvals: :manual,
                   file_scope: "/srv/tenant-1/session",
                   allowed_tools: ["test.session.prompt"]
                 },
                 target_id: "target-asm-session"
               )
             )

    assert error.reason ==
             {:target_incompatible, "target-asm-session", :missing_required_features}

    assert error.run.status == :failed
    assert error.run.target_id == "target-asm-session"
    assert error.attempt == nil
    assert [%Event{attempt: nil, type: "run.failed"}] = ControlPlane.events(error.run.run_id)
  end

  test "records a denied run without creating an attempt" do
    connection_id = install_connection!("tester", ["echo:read"], %{access_token: "test"})
    assert :ok = ControlPlane.register_connector(TestConnector)

    assert {:error, error} =
             ControlPlane.invoke(
               "test.echo",
               %{value: "nope"},
               invoke_opts(connection_id, trace_id: "trace-policy-scope-denial")
             )

    assert error.reason == :policy_denied
    assert error.run.status == :denied
    assert error.attempt == nil
    assert error.policy_decision.reasons == ["missing required scopes: echo:write"]

    assert {:ok, stored_run} = ControlPlane.fetch_run(error.run.run_id)
    assert stored_run.result.policy.actor_id == "control-plane-test"
    assert stored_run.result.policy.tenant_id == "tenant-1"
    assert stored_run.result.policy.environment == :prod
    assert stored_run.result.policy.trace_id == "trace-policy-scope-denial"
    assert stored_run.result.policy.connector_id == "test"
    assert stored_run.result.policy.capability_id == "test.echo"
    assert stored_run.result.policy.runtime_class == :direct
    assert stored_run.result.policy.sandbox.level == :strict
    assert stored_run.result.policy.reasons == ["missing required scopes: echo:write"]

    assert [
             %Event{
               attempt: nil,
               attempt_id: nil,
               seq: 0,
               type: "run.denied",
               payload: %{reasons: ["missing required scopes: echo:write"]}
             },
             %Event{
               attempt: nil,
               attempt_id: nil,
               seq: 1,
               type: "audit.policy_denied",
               payload: audit_payload,
               trace: %{trace_id: "trace-policy-scope-denial"}
             }
           ] = ControlPlane.events(error.run.run_id)

    assert audit_payload.actor_id == "control-plane-test"
    assert audit_payload.tenant_id == "tenant-1"
    assert audit_payload.connector_id == "test"
    assert audit_payload.capability_id == "test.echo"
    assert audit_payload.runtime_class == :direct
    assert audit_payload.reasons == ["missing required scopes: echo:write"]
  end

  test "routes session work through the authored jido_session harness driver when a compatible target is selected" do
    connection_id = install_connection!("tester", ["session:execute"], %{access_token: "test"})
    assert :ok = ControlPlane.register_connector(JidoSessionConnector)

    assert :ok =
             ControlPlane.announce_target(
               harness_target(
                 "target-jido-session",
                 "test.session.prompt",
                 :session,
                 "jido_session"
               )
             )

    assert {:ok, first} =
             ControlPlane.invoke(
               "test.session.prompt",
               %{prompt: "Draft a review packet"},
               invoke_opts(
                 connection_id,
                 allowed_operations: ["test.session.prompt"],
                 sandbox: %{
                   level: :strict,
                   egress: :restricted,
                   approvals: :manual,
                   file_scope: "/srv/tenant-1/session",
                   allowed_tools: ["test.session.prompt"]
                 },
                 target_id: "target-jido-session"
               )
             )

    assert {:ok, second} =
             ControlPlane.invoke(
               "test.session.prompt",
               %{prompt: "Turn it into a checklist"},
               invoke_opts(
                 connection_id,
                 allowed_operations: ["test.session.prompt"],
                 sandbox: %{
                   level: :strict,
                   egress: :restricted,
                   approvals: :manual,
                   file_scope: "/srv/tenant-1/session",
                   allowed_tools: ["test.session.prompt"]
                 },
                 target_id: "target-jido-session"
               )
             )

    assert first.run.runtime_class == :session
    assert first.attempt.runtime_ref_id == second.attempt.runtime_ref_id
    assert first.output.text == "handled: Draft a review packet"
    assert second.output.text == "handled: Turn it into a checklist"

    assert Enum.any?(ControlPlane.events(second.run.run_id), fn event ->
             event.session_id == second.attempt.runtime_ref_id and
               event.runtime_ref_id == second.attempt.runtime_ref_id
           end)
  end

  test "routes stream work through the authored asm harness driver when a compatible target is selected" do
    connection_id = install_connection!("tester", ["stream:execute"], %{access_token: "test"})
    assert :ok = ControlPlane.register_connector(AsmStreamConnector)

    assert :ok =
             ControlPlane.announce_target(
               harness_target("target-asm-stream", "test.asm.stream", :stream, "asm")
             )

    assert {:ok, first} =
             ControlPlane.invoke(
               "test.asm.stream",
               %{prompt: "Stream the current status"},
               invoke_opts(
                 connection_id,
                 allowed_operations: ["test.asm.stream"],
                 sandbox: %{
                   level: :standard,
                   egress: :restricted,
                   approvals: :auto,
                   file_scope: "/srv/tenant-1/asm",
                   allowed_tools: ["test.asm.stream"]
                 },
                 target_id: "target-asm-stream"
               )
             )

    assert {:ok, second} =
             ControlPlane.invoke(
               "test.asm.stream",
               %{prompt: "Stream the next status"},
               invoke_opts(
                 connection_id,
                 allowed_operations: ["test.asm.stream"],
                 sandbox: %{
                   level: :standard,
                   egress: :restricted,
                   approvals: :auto,
                   file_scope: "/srv/tenant-1/asm",
                   allowed_tools: ["test.asm.stream"]
                 },
                 target_id: "target-asm-stream"
               )
             )

    assert first.run.runtime_class == :stream
    assert first.attempt.runtime_ref_id == second.attempt.runtime_ref_id
    assert first.output.text == "hello from control plane"
    assert second.output.text == "hello from control plane"

    assert Enum.any?(ControlPlane.events(second.run.run_id), fn event ->
             event.session_id == second.attempt.runtime_ref_id and
               event.runtime_ref_id == second.attempt.runtime_ref_id
           end)
  end

  test "records actor and tenant denials as durable truth before attempt creation" do
    connection_id = install_connection!("tester", ["echo:write"], %{access_token: "test"})
    assert :ok = ControlPlane.register_connector(TestConnector)

    assert {:error, error} =
             ControlPlane.invoke(
               "test.echo",
               %{value: "nope"},
               invoke_opts(
                 connection_id,
                 actor_id: nil,
                 tenant_id: "tenant-2",
                 trace_id: "trace-policy-actor-tenant-denial"
               )
             )

    assert error.reason == :policy_denied
    assert error.run.status == :denied
    assert error.attempt == nil
    assert "actor_id is required" in error.policy_decision.reasons

    assert "tenant tenant-2 cannot use credential for tenant tenant-1" in error.policy_decision.reasons

    assert :error = ControlPlane.fetch_attempt("#{error.run.run_id}:1")

    assert [
             %Event{attempt: nil, attempt_id: nil, seq: 0, type: "run.denied"},
             %Event{
               attempt: nil,
               attempt_id: nil,
               seq: 1,
               type: "audit.policy_denied",
               payload: audit_payload,
               trace: %{trace_id: "trace-policy-actor-tenant-denial"}
             }
           ] = ControlPlane.events(error.run.run_id)

    assert "actor_id is required" in audit_payload.reasons
    assert "tenant tenant-2 cannot use credential for tenant tenant-1" in audit_payload.reasons
  end

  test "records a shed run without creating an attempt" do
    connection_id = install_connection!("tester", ["echo:write"], %{access_token: "test"})
    assert :ok = ControlPlane.register_connector(TestConnector)

    assert {:error, error} =
             ControlPlane.invoke(
               "test.echo",
               %{value: "later"},
               invoke_opts(
                 connection_id,
                 trace_id: "trace-policy-shed",
                 pressure: %{
                   decision: :shed,
                   reason: "dispatch queue saturated",
                   scope: "tenant-1:test"
                 }
               )
             )

    assert error.reason == :policy_shed
    assert error.run.status == :shed
    assert error.attempt == nil
    assert error.policy_decision.status == :shed
    assert error.policy_decision.reasons == ["dispatch queue saturated"]

    assert {:ok, stored_run} = ControlPlane.fetch_run(error.run.run_id)
    assert stored_run.result.policy.status == :shed
    assert stored_run.result.policy.trace_id == "trace-policy-shed"
    assert stored_run.result.policy.pressure.reason == "dispatch queue saturated"
    assert stored_run.result.policy.pressure.scope == "tenant-1:test"

    assert [
             %Event{
               attempt: nil,
               attempt_id: nil,
               seq: 0,
               type: "run.shed",
               payload: %{reasons: ["dispatch queue saturated"]}
             },
             %Event{
               attempt: nil,
               attempt_id: nil,
               seq: 1,
               type: "audit.policy_shed",
               payload: audit_payload,
               trace: %{trace_id: "trace-policy-shed"}
             }
           ] = ControlPlane.events(error.run.run_id)

    assert audit_payload.pressure.reason == "dispatch queue saturated"
    assert audit_payload.pressure.scope == "tenant-1:test"
  end

  test "redacts credential lease material from durable run attempt and event truth" do
    connection_id =
      install_connection!("leaky-user", ["echo:write"], %{
        access_token: "gho_never_persist_me",
        refresh_token: "ghr_never_persist_me"
      })

    assert :ok = ControlPlane.register_connector(LeakyConnector)

    assert {:ok, result} =
             ControlPlane.invoke("leaky.echo", %{value: "ok"}, invoke_opts(connection_id))

    assert {:ok, stored_run} = ControlPlane.fetch_run(result.run.run_id)
    assert {:ok, stored_attempt} = ControlPlane.fetch_attempt(result.attempt.attempt_id)
    events = ControlPlane.events(result.run.run_id)

    refute inspect(stored_run.result) =~ "gho_never_persist_me"
    refute inspect(stored_attempt.output) =~ "gho_never_persist_me"
    refute Enum.any?(events, &(inspect(&1.payload) =~ "gho_never_persist_me"))

    assert stored_attempt.output.credential_lease == Redaction.redacted()
    assert stored_attempt.output.echoed_secret == Redaction.redacted()
  end

  test "admits trigger truth into the control plane without creating an attempt" do
    assert :ok = ControlPlane.register_connector(TestConnector)

    trigger =
      TriggerRecord.new!(%{
        source: :webhook,
        connector_id: "test",
        trigger_id: "echo.opened",
        capability_id: "test.echo",
        tenant_id: "tenant-1",
        external_id: "delivery-1",
        dedupe_key: "delivery-1",
        payload: %{"value" => "ok"},
        signal: %{"type" => "test.echo.opened", "source" => "/ingress/webhook/test"}
      })

    checkpoint =
      TriggerCheckpoint.new!(%{
        tenant_id: "tenant-1",
        connector_id: "test",
        trigger_id: "echo.opened",
        partition_key: "tenant-1",
        cursor: "cursor-1",
        last_event_id: "delivery-1"
      })

    assert {:ok, result} =
             ControlPlane.admit_trigger(trigger, checkpoint: checkpoint, dedupe_ttl_seconds: 60)

    assert result.status == :accepted
    assert result.run.status == :accepted

    assert {:ok, persisted_trigger} =
             ControlPlane.fetch_trigger("tenant-1", "test", "echo.opened", "delivery-1")

    assert persisted_trigger.run_id == result.run.run_id

    assert {:ok, persisted_checkpoint} =
             ControlPlane.fetch_trigger_checkpoint("tenant-1", "test", "echo.opened", "tenant-1")

    assert persisted_checkpoint.cursor == "cursor-1"
    assert [%Event{attempt: nil, type: "run.accepted"}] = ControlPlane.events(result.run.run_id)
    assert :error = ControlPlane.fetch_attempt("#{result.run.run_id}:1")
  end

  test "records rejected trigger truth without creating a run" do
    trigger =
      TriggerRecord.new!(%{
        source: :webhook,
        connector_id: "test",
        trigger_id: "echo.invalid",
        capability_id: "test.echo",
        tenant_id: "tenant-1",
        external_id: "delivery-invalid",
        dedupe_key: "delivery-invalid",
        payload: %{"value" => "bad"},
        signal: %{"type" => "test.echo.invalid", "source" => "/ingress/webhook/test"}
      })

    assert {:ok, rejected_trigger} =
             ControlPlane.record_rejected_trigger(trigger, {:invalid_trigger, :bad_payload})

    assert rejected_trigger.status == :rejected
    assert is_nil(rejected_trigger.run_id)

    assert {:ok, persisted_trigger} =
             ControlPlane.fetch_trigger("tenant-1", "test", "echo.invalid", "delivery-invalid")

    assert persisted_trigger.rejection_reason == {:invalid_trigger, :bad_payload}
  end

  test "records artifact references as stable control-plane truth" do
    checksum = "sha256:" <> String.duplicate("a", 64)

    artifact_ref =
      ArtifactRef.new!(%{
        artifact_id: "artifact-control-plane-1",
        run_id: "run-control-plane-1",
        attempt_id: "run-control-plane-1:1",
        artifact_type: :stdout,
        transport_mode: :object_store,
        checksum: checksum,
        size_bytes: 64,
        payload_ref: %{
          store: "s3",
          key: "sha256:" <> String.duplicate("b", 64),
          ttl_s: 86_400,
          access_control: :run_scoped,
          checksum: checksum,
          size_bytes: 64
        },
        retention_class: "stdout_stderr",
        redaction_status: :clear
      })

    assert :ok = ControlPlane.record_artifact(artifact_ref)
    assert {:ok, persisted_artifact} = ControlPlane.fetch_artifact("artifact-control-plane-1")
    assert [listed_artifact] = ControlPlane.run_artifacts("run-control-plane-1")
    assert persisted_artifact == artifact_ref
    assert listed_artifact == artifact_ref
  end

  test "announces targets and exposes compatible target matches" do
    incompatible_target =
      TargetDescriptor.new!(%{
        target_id: "target-degraded",
        capability_id: "python3",
        runtime_class: :direct,
        version: "2.0.0",
        features: %{
          feature_ids: ["python3"],
          runspec_versions: ["1.0.0"],
          event_schema_versions: ["1.0.0"]
        },
        constraints: %{},
        health: :degraded,
        location: %{mode: :beam, region: "us-west-2"}
      })

    compatible_target =
      TargetDescriptor.new!(%{
        target_id: "target-healthy",
        capability_id: "python3",
        runtime_class: :direct,
        version: "2.1.0",
        features: %{
          feature_ids: ["docker", "python3"],
          runspec_versions: ["1.0.0", "1.1.0"],
          event_schema_versions: ["1.0.0", "1.2.0"]
        },
        constraints: %{regions: ["us-west-2"]},
        health: :healthy,
        location: %{mode: :beam, region: "us-west-2", workspace_root: "/srv/jido"}
      })

    assert :ok = ControlPlane.announce_target(incompatible_target)
    assert :ok = ControlPlane.announce_target(compatible_target)
    assert {:ok, stored_target} = ControlPlane.fetch_target("target-healthy")

    assert stored_target == compatible_target

    assert [
             %{
               target: %TargetDescriptor{target_id: "target-healthy"},
               negotiated_versions: %{
                 runspec_version: "1.1.0",
                 event_schema_version: "1.2.0"
               }
             }
           ] =
             ControlPlane.compatible_targets(%{
               capability_id: "python3",
               runtime_class: :direct,
               version_requirement: "~> 2.0",
               required_features: ["docker"],
               accepted_runspec_versions: ["1.0.0", "1.1.0"],
               accepted_event_schema_versions: ["1.0.0", "1.2.0"]
             })
  end

  defp install_connection!(subject, scopes, secret) do
    now = Contracts.now()

    assert {:ok, %{install: %Install{} = install, connection: %Connection{} = connection}} =
             Auth.start_install("test", "tenant-1", %{
               actor_id: "control-plane-test",
               auth_type: :oauth2,
               subject: subject,
               requested_scopes: scopes,
               now: now
             })

    install_id = install.install_id
    connection_id = connection.connection_id

    assert {:ok,
            %{
              install: %Install{install_id: ^install_id},
              connection: %Connection{connection_id: ^connection_id},
              credential_ref: %CredentialRef{}
            }} =
             Auth.complete_install(install.install_id, %{
               subject: subject,
               granted_scopes: scopes,
               secret: secret,
               expires_at: DateTime.add(now, 7 * 24 * 3_600, :second),
               now: now
             })

    connection_id
  end

  defp invoke_opts(connection_id, overrides \\ []) do
    defaults = [
      connection_id: connection_id,
      actor_id: "control-plane-test",
      tenant_id: "tenant-1",
      environment: :prod,
      trace_id: "trace-control-plane-test",
      allowed_operations: ["test.echo", "leaky.echo"],
      sandbox: %{
        level: :strict,
        egress: :restricted,
        approvals: :auto,
        file_scope: "/srv/tenant-1",
        allowed_tools: ["connector.echo"]
      }
    ]

    Keyword.merge(defaults, overrides)
  end

  defp echo_target(target_id, overrides \\ []) do
    runtime_class = Keyword.get(overrides, :runtime_class, :direct)
    capability_id = Keyword.get(overrides, :capability_id, "test.echo")
    health = Keyword.get(overrides, :health, :healthy)

    TargetDescriptor.new!(%{
      target_id: target_id,
      capability_id: capability_id,
      runtime_class: runtime_class,
      version: "1.0.0",
      features: %{
        feature_ids: ["connector.echo"],
        runspec_versions: ["1.0.0"],
        event_schema_versions: ["1.0.0"]
      },
      constraints: %{workspace_root: "/srv/tenant-1"},
      health: health,
      location: %{mode: :beam, region: "test", workspace_root: "/srv/tenant-1"}
    })
  end

  defp harness_target(target_id, capability_id, runtime_class, driver_id) do
    TargetDescriptor.new!(%{
      target_id: target_id,
      capability_id: capability_id,
      runtime_class: runtime_class,
      version: "1.0.0",
      features: %{
        feature_ids: [driver_id, capability_id],
        runspec_versions: ["1.0.0"],
        event_schema_versions: ["1.0.0"]
      },
      constraints: %{workspace_root: "/srv/tenant-1"},
      health: :healthy,
      location: %{mode: :beam, region: "test", workspace_root: "/srv/tenant-1"}
    })
  end
end
