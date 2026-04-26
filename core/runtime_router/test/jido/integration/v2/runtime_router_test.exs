defmodule Jido.Integration.V2.RuntimeRouterTest do
  use ExUnit.Case

  alias Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriver
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.ExecutionGovernanceProjection
  alias Jido.Integration.V2.RuntimeRouter
  alias Jido.Integration.V2.RuntimeRouter.ExecutionPlaneBoundary
  alias Jido.Integration.V2.TargetDescriptor
  alias Jido.RuntimeControl.SessionHandle

  defmodule AuthoredDriver do
    alias Jido.RuntimeControl.{ExecutionResult, ExecutionStatus, RunRequest, SessionHandle}

    def start_session(opts) when is_list(opts) do
      send(self(), {:authored_driver_start_session, opts})

      {:ok,
       SessionHandle.new!(%{
         session_id: "authored-session",
         runtime_id: :authored_driver,
         provider: Keyword.get(opts, :provider),
         status: :ready,
         metadata: %{}
       })}
    end

    def run(%SessionHandle{} = session, %RunRequest{} = request, opts) when is_list(opts) do
      send(self(), {:authored_driver_run, session.session_id, request.prompt, opts})

      {:ok,
       ExecutionResult.new!(%{
         run_id: Keyword.get(opts, :run_id, "authored-run"),
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

    def cancel_run(%SessionHandle{} = session, run_id) when is_binary(run_id) do
      send(self(), {:authored_driver_cancel_run, session.session_id, run_id})
      :ok
    end

    def session_status(%SessionHandle{} = session) do
      send(self(), {:authored_driver_session_status, session.session_id})

      {:ok,
       ExecutionStatus.new!(%{
         runtime_id: session.runtime_id,
         session_id: session.session_id,
         scope: :session,
         state: :ready,
         timestamp: "2026-04-25T00:00:00Z",
         message: "ready",
         details: %{"provider" => Atom.to_string(session.provider)}
       })}
    end

    def approve(%SessionHandle{} = session, approval_id, decision, opts)
        when is_binary(approval_id) and decision in [:allow, :deny] and is_list(opts) do
      send(self(), {:authored_driver_approve, session.session_id, approval_id, decision, opts})
      :ok
    end

    def stop_session(%SessionHandle{}), do: :ok
  end

  defmodule OverrideDriver do
    alias Jido.RuntimeControl.{ExecutionResult, RunRequest, SessionHandle}

    def start_session(opts) when is_list(opts) do
      send(self(), {:override_driver_start_session, opts})

      {:ok,
       SessionHandle.new!(%{
         session_id: "override-session",
         runtime_id: :override_driver,
         provider: Keyword.get(opts, :provider),
         status: :ready,
         metadata: %{}
       })}
    end

    def run(%SessionHandle{} = session, %RunRequest{} = request, opts) when is_list(opts) do
      send(self(), {:override_driver_run, session.session_id, request.prompt, opts})

      {:ok,
       ExecutionResult.new!(%{
         run_id: Keyword.get(opts, :run_id, "override-run"),
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

    def stop_session(%SessionHandle{}), do: :ok
  end

  defmodule FallbackRuntimeClient do
    @behaviour ExecutionPlane.Runtime.Client

    alias ExecutionPlane.Admission.Rejection
    alias ExecutionPlane.ExecutionResult, as: PlaneExecutionResult
    alias ExecutionPlane.Runtime.NodeDescriptor

    def describe(_opts), do: {:ok, NodeDescriptor.new!(node_id: "stub-remote-node")}

    def admit(request, _opts), do: {:error, Rejection.new(:not_implemented, request.request_id)}

    def execute(request, opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      attestation_class = List.first(request.acceptable_attestation.classes)
      send(test_pid, {:execution_plane_execute, attestation_class, request})

      if attestation_class == Keyword.fetch!(opts, :succeed_on) do
        {:ok,
         PlaneExecutionResult.new!(
           execution_ref: "exec-#{attestation_class}",
           status: "succeeded",
           output: %{"attestation_class" => attestation_class},
           evidence: [
             %{
               "evidence_type" => "execution.completed",
               "attestation_class" => attestation_class
             }
           ],
           provenance: request.provenance
         )}
      else
        {:error,
         PlaneExecutionResult.new!(
           execution_ref: "exec-#{attestation_class}",
           status: "rejected",
           error: %{"reason" => "no_target_for_attestation"},
           provenance: request.provenance
         )}
      end
    end

    def stream(_request, _opts), do: {:error, Rejection.new(:not_implemented, "stream")}
    def cancel(_execution_ref, _opts), do: :ok
  end

  setup do
    RuntimeRouter.start!()

    previous_runtime_drivers =
      Application.get_env(:jido_integration_v2_control_plane, :runtime_drivers)

    Application.delete_env(:jido_integration_v2_control_plane, :runtime_drivers)
    RuntimeRouter.reset!()

    on_exit(fn ->
      case previous_runtime_drivers do
        nil ->
          Application.delete_env(:jido_integration_v2_control_plane, :runtime_drivers)

        runtime_drivers ->
          Application.put_env(
            :jido_integration_v2_control_plane,
            :runtime_drivers,
            runtime_drivers
          )
      end

      RuntimeRouter.reset!()
    end)

    :ok
  end

  test "start!/0 boots the runtime router and its declared runtime dependencies" do
    stop_runtime_router!()

    assert :ok = RuntimeRouter.start!()
    assert :ok = RuntimeRouter.start!()

    assert Process.whereis(Jido.Integration.V2.RuntimeRouter.Supervisor)
    assert Process.whereis(Jido.Integration.V2.RuntimeRouter.SessionStore)
    assert Process.whereis(Jido.Integration.V2.AsmRuntimeBridge.SessionStore)
    assert Process.whereis(Jido.Session.Store)
  end

  test "publishes asm and jido_session as the only built-in Runtime Control driver ids" do
    assert RuntimeRouter.target_driver_ids() == ["asm", "jido_session"]
    assert RuntimeRouter.driver_modules() |> Map.keys() |> Enum.sort() == ["asm", "jido_session"]
  end

  test "does not resolve removed bridge runtime drivers" do
    refute function_exported?(RuntimeRouter, :compatibility_driver_ids, 0)
    assert :error = RuntimeRouter.driver_module(removed_session_bridge_id())
    assert :error = RuntimeRouter.driver_module(removed_stream_bridge_id())
  end

  test "resolves asm to the target Runtime Router driver" do
    assert {:ok, RuntimeControlDriver} = RuntimeRouter.driver_module("asm")
    assert {:ok, Jido.Session.RuntimeControlDriver} = RuntimeRouter.driver_module("jido_session")
  end

  test "passes authored runtime options through to the selected Runtime Control driver" do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{authored_driver: AuthoredDriver}
    )

    assert {:ok, _result} =
             RuntimeRouter.execute(
               capability_fixture(%{
                 runtime: %{
                   driver: "authored_driver",
                   provider: :codex,
                   options: %{
                     "lane" => "sdk",
                     "approval_mode" => "manual"
                   }
                 }
               }),
               %{prompt: "hello"},
               runtime_context()
             )

    assert_receive {:authored_driver_start_session, start_opts}
    assert start_opts[:provider] == :codex
    assert start_opts[:lane] == "sdk"
    assert start_opts[:approval_mode] == "manual"

    assert_receive {:authored_driver_run, "authored-session", "hello", run_opts}
    assert run_opts[:provider] == :codex
    assert run_opts[:lane] == "sdk"
    assert run_opts[:approval_mode] == "manual"
  end

  test "requires an authored runtime driver for non-direct capabilities" do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{asm: AuthoredDriver}
    )

    assert {:error, {:missing_runtime_driver, :session}, runtime_result} =
             RuntimeRouter.execute(
               capability_fixture(%{
                 runtime: %{
                   provider: :codex,
                   options: %{
                     "lane" => "sdk"
                   }
                 }
               }),
               %{prompt: "hello"},
               runtime_context()
             )

    assert Enum.map(runtime_result.events, & &1.type) == ["attempt.started", "attempt.failed"]
    refute_received {:authored_driver_start_session, _opts}
  end

  test "does not let target descriptors override authored routing metadata" do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{
        authored_driver: AuthoredDriver,
        override_driver: OverrideDriver
      }
    )

    assert {:ok, _result} =
             RuntimeRouter.execute(
               capability_fixture(),
               %{prompt: "hello"},
               runtime_context(
                 target_descriptor_fixture(%{
                   "driver" => "override_driver",
                   "provider" => "claude",
                   "options" => %{"lane" => "target"}
                 })
               )
             )

    assert_receive {:authored_driver_start_session, start_opts}
    assert start_opts[:provider] == :codex
    refute_received {:override_driver_start_session, _opts}

    assert_receive {:authored_driver_run, "authored-session", "hello", run_opts}
    assert run_opts[:provider] == :codex
    refute_received {:override_driver_run, _session_id, _prompt, _opts}
  end

  test "routes session-control start without constructing a prompt fallback" do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{authored_driver: AuthoredDriver}
    )

    assert {:ok, result} =
             RuntimeRouter.execute(
               capability_fixture(%{
                 id: "codex.session.start",
                 session_control_operation: :start
               }),
               %{},
               runtime_context()
             )

    assert result.output.status == :ready
    assert result.output.session_id == "authored-session"
    assert result.output.operation == :start
    assert Enum.map(result.events, & &1.type) == ["session.started", "session_control.started"]

    assert_receive {:authored_driver_start_session, _opts}
    refute_received {:authored_driver_run, _session_id, _prompt, _opts}
  end

  test "routes session-control status to session_status without running a prompt turn" do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{authored_driver: AuthoredDriver}
    )

    put_session_store_entry("authored-session")

    assert {:ok, result} =
             RuntimeRouter.execute(
               capability_fixture(%{
                 id: "codex.session.status",
                 session_control_operation: :status
               }),
               %{session_id: "authored-session"},
               runtime_context()
             )

    assert result.output.status == :ready
    assert result.output.session_id == "authored-session"
    assert result.output.operation == :status

    assert_receive {:authored_driver_session_status, "authored-session"}
    refute_received {:authored_driver_start_session, _opts}
    refute_received {:authored_driver_run, _session_id, _prompt, _opts}
  end

  test "routes session-control cancel to cancel_run with explicit ids" do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{authored_driver: AuthoredDriver}
    )

    put_session_store_entry("authored-session")

    assert {:ok, result} =
             RuntimeRouter.execute(
               capability_fixture(%{
                 id: "codex.session.cancel",
                 session_control_operation: :cancel
               }),
               %{session_id: "authored-session", run_id: "run-to-cancel"},
               runtime_context()
             )

    assert result.output.status == :ready
    assert result.output.session_id == "authored-session"
    assert result.output.run_id == "run-to-cancel"
    assert result.output.operation == :cancel

    assert_receive {:authored_driver_cancel_run, "authored-session", "run-to-cancel"}
    assert_receive {:authored_driver_session_status, "authored-session"}
    refute_received {:authored_driver_start_session, _opts}
    refute_received {:authored_driver_run, _session_id, _prompt, _opts}
  end

  test "routes session-control approve to approve with explicit approval id and decision" do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{authored_driver: AuthoredDriver}
    )

    put_session_store_entry("authored-session")

    assert {:ok, result} =
             RuntimeRouter.execute(
               capability_fixture(%{
                 id: "codex.session.approve",
                 session_control_operation: :approve
               }),
               %{session_id: "authored-session", approval_id: "approval-1", decision: :allow},
               runtime_context()
             )

    assert result.output.status == :ready
    assert result.output.session_id == "authored-session"
    assert result.output.approval_id == "approval-1"
    assert result.output.decision == :allow
    assert result.output.operation == :approve

    assert_receive {:authored_driver_approve, "authored-session", "approval-1", :allow, _opts}
    assert_receive {:authored_driver_session_status, "authored-session"}
    refute_received {:authored_driver_start_session, _opts}
    refute_received {:authored_driver_run, _session_id, _prompt, _opts}
  end

  test "returns structured validation errors for out-of-band control without session_id" do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{authored_driver: AuthoredDriver}
    )

    assert {:error, %Jido.RuntimeControl.Error.InvalidInputError{} = error, result} =
             RuntimeRouter.execute(
               capability_fixture(%{
                 id: "codex.session.status",
                 session_control_operation: :status
               }),
               %{},
               runtime_context()
             )

    assert error.field == :session_id
    assert error.details == %{operation: :status}
    assert result.output == nil
    assert Enum.map(result.events, & &1.type) == ["attempt.started", "attempt.failed"]

    refute_received {:authored_driver_start_session, _opts}
    refute_received {:authored_driver_run, _session_id, _prompt, _opts}
  end

  test "fails loudly when the runtime router application is not started" do
    stop_runtime_router!()

    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{authored_driver: AuthoredDriver}
    )

    assert_raise ArgumentError, ~r/call Jido\.Integration\.V2\.RuntimeRouter\.start!\/0/, fn ->
      RuntimeRouter.execute(
        capability_fixture(),
        %{prompt: "hello"},
        runtime_context()
      )
    end
  end

  test "maps governance into admission requests without rewriting acceptable attestations" do
    projection = execution_governance_projection()

    request =
      ExecutionPlaneBoundary.admission_request(
        projection,
        %{"prompt" => "hello"},
        request_id: "request-map-1"
      )

    assert request.request_id == "request-map-1"
    assert request.lane_id == "process"
    assert request.operation == "runtime.session"

    assert request.acceptable_attestation.classes == [
             "spiffe://prod/microvm-strict@v1",
             "local-erlexec-weak"
           ]

    assert request.sandbox_profile.bundle_hash ==
             ExecutionGovernanceProjection.payload_hash(projection)

    assert request.sandbox_profile.opaque_bundle ==
             ExecutionGovernanceProjection.dump(projection)

    assert request.authority_ref.metadata["decision_id"] == "decision-1"
    assert request.provenance.owner == "jido_integration"
  end

  test "owns the Execution Plane fallback ladder over separate runtime-client calls" do
    assert {:ok, result, attempts} =
             ExecutionPlaneBoundary.execute_fallback_ladder(
               execution_governance_projection(),
               %{"prompt" => "hello"},
               FallbackRuntimeClient,
               runtime_client_opts: [
                 test_pid: self(),
                 succeed_on: "local-erlexec-weak"
               ]
             )

    assert result.status == "succeeded"

    assert Enum.map(attempts, &{&1.rung, &1.attestation_class, &1.status}) == [
             {1, "spiffe://prod/microvm-strict@v1", :rejected},
             {2, "local-erlexec-weak", :succeeded}
           ]

    assert_receive {:execution_plane_execute, "spiffe://prod/microvm-strict@v1", first_request}
    assert first_request.acceptable_attestation.classes == ["spiffe://prod/microvm-strict@v1"]

    assert_receive {:execution_plane_execute, "local-erlexec-weak", second_request}
    assert second_request.acceptable_attestation.classes == ["local-erlexec-weak"]
  end

  defp capability_fixture(overrides \\ %{}) do
    runtime =
      Map.get(overrides, :runtime, %{
        driver: "authored_driver",
        provider: :codex,
        options: %{
          "lane" => "sdk"
        }
      })

    Capability.new!(%{
      id: Map.get(overrides, :id, "test.session.exec"),
      connector: "test",
      runtime_class: :session,
      kind: :operation,
      transport_profile: :stdio,
      handler: __MODULE__,
      metadata:
        %{
          runtime: runtime
        }
        |> maybe_put_session_control(Map.get(overrides, :session_control_operation))
    })
  end

  defp maybe_put_session_control(metadata, nil), do: metadata

  defp maybe_put_session_control(metadata, operation) when is_atom(operation) do
    Map.put(metadata, :session_control, %{operation: operation})
  end

  defp put_session_store_entry(session_id) do
    Jido.Integration.V2.RuntimeRouter.SessionStore.put(
      {:test_session_id, session_id},
      %{
        driver_module: AuthoredDriver,
        session:
          SessionHandle.new!(%{
            session_id: session_id,
            runtime_id: :authored_driver,
            provider: :codex,
            status: :ready,
            metadata: %{}
          })
      }
    )
  end

  defp runtime_context(target_descriptor \\ nil) do
    %{
      run_id: "run-1",
      attempt_id: "run-1:1",
      credential_ref: %{id: "cred-1"},
      target_descriptor: target_descriptor,
      policy_inputs: %{
        execution: %{
          sandbox: %{
            allowed_tools: ["test.session.exec"],
            file_scope: "/tmp/runtime"
          }
        }
      }
    }
  end

  defp target_descriptor_fixture(runtime_extensions) do
    TargetDescriptor.new!(%{
      target_id: "target-1",
      capability_id: "test.session.exec",
      runtime_class: :session,
      version: "1.0.0",
      features: %{
        feature_ids: ["test.session.exec"],
        runspec_versions: ["1.0.0"],
        event_schema_versions: ["1.0.0"]
      },
      constraints: %{},
      health: :healthy,
      location: %{mode: :beam, region: "test", workspace_root: "/tmp/runtime"},
      extensions: %{"runtime" => runtime_extensions}
    })
  end

  defp execution_governance_projection do
    ExecutionGovernanceProjection.new!(%{
      contract_version: "v1",
      execution_governance_id: "governance-runtime-router-1",
      authority_ref: %{
        "decision_id" => "decision-1",
        "policy_version" => "policy-2026-04-24",
        "decision_hash" => String.duplicate("a", 64)
      },
      sandbox: %{
        "level" => "strict",
        "egress" => "restricted",
        "approvals" => "manual",
        "acceptable_attestation" => [
          "spiffe://prod/microvm-strict@v1",
          "local-erlexec-weak"
        ],
        "allowed_tools" => ["bash"],
        "file_scope_ref" => "workspace://tenant/project",
        "file_scope_hint" => "/workspace/project"
      },
      boundary: %{
        "boundary_class" => "workspace_session",
        "trust_profile" => "trusted_operator",
        "requested_attach_mode" => "fresh_or_reuse",
        "requested_ttl_ms" => 60_000
      },
      topology: %{
        "topology_intent_id" => "topology-1",
        "session_mode" => "attached",
        "coordination_mode" => "single_target",
        "topology_epoch" => 1,
        "routing_hints" => %{"runtime_driver" => "asm"}
      },
      workspace: %{
        "workspace_profile" => "project_workspace",
        "logical_workspace_ref" => "workspace://tenant/project",
        "mutability" => "read_write"
      },
      resources: %{
        "resource_profile" => "standard",
        "cpu_class" => nil,
        "memory_class" => nil,
        "wall_clock_budget_ms" => 120_000
      },
      placement: %{
        "execution_family" => "process",
        "placement_intent" => "host_local",
        "target_kind" => "cli",
        "node_affinity" => "same-node"
      },
      operations: %{
        "allowed_operations" => ["runtime.session"],
        "effect_classes" => ["process"]
      },
      extensions: %{}
    })
  end

  defp removed_session_bridge_id, do: removed_bridge_id("session")
  defp removed_stream_bridge_id, do: removed_bridge_id("stream")

  defp removed_bridge_id(kind) do
    ["integration", kind, "bridge"]
    |> Enum.join("_")
  end

  defp stop_runtime_router! do
    RuntimeRouter.stop!()
  end
end
