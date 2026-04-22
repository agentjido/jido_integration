defmodule Jido.Integration.V2.StorePostgres.ProfileRegistryStoreTest do
  use Jido.Integration.V2.StorePostgres.DataCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Jido.Integration.V2.SimulationProfileRegistryEntry
  alias Jido.Integration.V2.StorePostgres.ProfileRegistryStore
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.TestSupport

  test "persists install, update, selection, cleanup failure, and remove lifecycle evidence" do
    Sandbox.checkin(Repo)
    Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      TestSupport.reset_database!()
      Sandbox.mode(Repo, :auto)
    end)

    assert {:ok, installed} =
             ProfileRegistryStore.install_profile(profile_attrs(), installed_scenarios(), %{
               owner_refs: ["owner://jido_integration/service-profile"],
               audit_install_actor_ref: "actor://operator/install",
               audit_install_timestamp: ~U[2026-04-22 12:00:00Z]
             })

    assert %SimulationProfileRegistryEntry{} = installed
    assert installed.profile_version == "1.0.0"
    assert installed.cleanup_status == :active

    assert {:ok, ^installed} =
             ProfileRegistryStore.select_profile(
               installed.profile_id,
               "local_dev_no_egress",
               "owner://jido_integration/service-profile"
             )

    assert {:error, :environment_mismatch} =
             ProfileRegistryStore.select_profile(
               installed.profile_id,
               "prod_real_provider",
               "owner://jido_integration/service-profile"
             )

    assert {:error, :missing_owner} =
             ProfileRegistryStore.select_profile(
               installed.profile_id,
               "local_dev_no_egress",
               "owner://execution_plane/lower"
             )

    assert {:error, :concurrent_install_same_id_different_version} =
             ProfileRegistryStore.install_profile(
               profile_attrs(%{version: "1.1.0"}),
               installed_scenarios(),
               %{
                 owner_refs: ["owner://jido_integration/service-profile"],
                 audit_install_actor_ref: "actor://operator/install"
               }
             )

    assert {:error, :stale_version} =
             ProfileRegistryStore.update_profile(
               profile_attrs(%{version: "1.0.0"}),
               installed_scenarios(),
               %{audit_update_history_ref: "audit://profile/update/stale"}
             )

    assert {:ok, updated} =
             ProfileRegistryStore.update_profile(
               profile_attrs(%{version: "1.1.0"}),
               installed_scenarios(),
               %{audit_update_history_ref: "audit://profile/update/1"}
             )

    assert updated.profile_version == "1.1.0"
    assert updated.audit_update_history_refs == ["audit://profile/update/1"]

    assert {:error, :cleanup_failure} =
             ProfileRegistryStore.remove_profile(updated.profile_id, %{
               audit_remove_actor_ref: "actor://operator/remove",
               cleanup_status: :cleanup_failed,
               cleanup_artifact_refs: ["artifact://profile/temp"]
             })

    assert {:ok, cleanup_failed} = ProfileRegistryStore.fetch_profile(updated.profile_id)
    assert cleanup_failed.cleanup_status == :cleanup_failed
    assert cleanup_failed.owner_evidence_refs == updated.owner_evidence_refs

    assert {:error, :stale_version} =
             ProfileRegistryStore.select_profile(
               cleanup_failed.profile_id,
               "local_dev_no_egress",
               "owner://jido_integration/service-profile"
             )

    assert {:ok, removable} =
             ProfileRegistryStore.install_profile(
               profile_attrs(%{
                 profile_id: "service-profile://phase6/jido/removable",
                 version: "1.0.0"
               }),
               installed_scenarios(),
               %{
                 owner_refs: ["owner://jido_integration/service-profile"],
                 audit_install_actor_ref: "actor://operator/install"
               }
             )

    assert {:ok, removed} =
             ProfileRegistryStore.remove_profile(removable.profile_id, %{
               audit_remove_actor_ref: "actor://operator/remove",
               cleanup_artifact_refs: ["artifact://profile/temp"]
             })

    assert removed.cleanup_status == :removed
    assert removed.audit_remove_actor_ref_or_null == "actor://operator/remove"
    assert removed.owner_evidence_refs == removable.owner_evidence_refs

    assert :ok = restart_repo!(:auto)

    assert {:ok, recovered_cleanup_failed} =
             ProfileRegistryStore.fetch_profile(cleanup_failed.profile_id)

    assert recovered_cleanup_failed.cleanup_status == :cleanup_failed
    assert recovered_cleanup_failed.cleanup_artifact_refs == ["artifact://profile/temp"]
    assert recovered_cleanup_failed.owner_evidence_refs == cleanup_failed.owner_evidence_refs
  end

  test "rejects every required install-time registry failure mode before persistence" do
    assert {:error, :missing_owner} =
             ProfileRegistryStore.install_profile(profile_attrs(), installed_scenarios(), %{
               owner_refs: [],
               audit_install_actor_ref: "actor://operator/install"
             })

    assert {:error, :missing_owner_evidence} =
             ProfileRegistryStore.install_profile(
               profile_attrs(%{owner_evidence_refs: []}),
               installed_scenarios(),
               %{
                 owner_refs: ["owner://jido_integration/service-profile"],
                 audit_install_actor_ref: "actor://operator/install"
               }
             )

    assert {:error, :missing_no_egress_policy} =
             ProfileRegistryStore.install_profile(
               profile_attrs(%{
                 no_egress_policy_ref: "no-egress-policy://phase6/allow-real-provider"
               }),
               installed_scenarios(),
               %{
                 owner_refs: ["owner://jido_integration/service-profile"],
                 audit_install_actor_ref: "actor://operator/install"
               }
             )

    assert {:error, :dangling_lower_scenario_ref} =
             ProfileRegistryStore.install_profile(
               profile_attrs(%{
                 lower_scenario_refs: ["lower-scenario://missing/owner/declaration"]
               }),
               installed_scenarios(),
               %{
                 owner_refs: ["owner://jido_integration/service-profile"],
                 audit_install_actor_ref: "actor://operator/install"
               }
             )

    assert {:error, :raw_body_allowed_when_policy_denies} =
             ProfileRegistryStore.install_profile(
               profile_attrs(%{
                 raw_body_policy: Map.put(profile_attrs().raw_body_policy, "raw_prompts", "allow")
               }),
               installed_scenarios(),
               %{
                 owner_refs: ["owner://jido_integration/service-profile"],
                 audit_install_actor_ref: "actor://operator/install"
               }
             )

    assert ProfileRegistryStore.list_profiles() == []
  end

  defp profile_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        profile_id: "service-profile://phase6/jido/local-llama",
        version: "1.0.0",
        owner_repo: "jido_integration",
        environment_scope: "local_dev_no_egress",
        workload_ref: "workload://app-kit/operator/governed-agent",
        pack_ref: "pack://extravaganza/coding_operations",
        work_class_ref: "work-class://extravaganza/coding_operations",
        subject_kind: "coding_task",
        tenant_policy_ref: "tenant-policy://citadel/phase6/default",
        authority_policy_ref: "authority-policy://citadel/phase6/default",
        authorization_scope_requirements: %{
          "required_scopes" => ["pack:use", "provider:simulate"],
          "denied_scopes" => ["provider:egress", "saas:write"]
        },
        provider_refs: ["provider://phase6/local-llama"],
        model_refs: ["model://phase6/llama-3.2-3b-instruct"],
        endpoint_refs: ["endpoint://jido/local-llama-openai-compatible"],
        budget_profile_ref: "budget-profile://stack-lab/phase6/no-spend",
        meter_profile_ref: "meter-profile://stack-lab/phase6/hash-only",
        lower_scenario_refs: ["lower-scenario://cli-subprocess-core/codex/process"],
        no_egress_policy_ref: "no-egress-policy://phase6/block-provider-and-saas",
        evidence_policy_ref: "evidence-policy://stack-lab/phase6/bounded-only",
        raw_body_policy: %{
          "durable_persistence" => "deny",
          "raw_prompts" => "deny",
          "raw_provider_bodies" => "deny",
          "full_workflow_histories" => "deny"
        },
        input_fingerprint_policy: %{
          "mode" => "transient_hash",
          "algorithm" => "sha256",
          "persist_raw_body?" => false
        },
        cleanup_policy: %{
          "mode" => "delete_runtime_artifacts",
          "retention" => "bounded_refs_only"
        },
        owner_evidence_refs: ["owner-evidence://jido-integration/contracts/service-profile"]
      },
      overrides
    )
  end

  defp installed_scenarios do
    [
      %{
        contract_version: "ExecutionPlane.LowerSimulationScenario.v1",
        scenario_id: "lower-scenario://cli-subprocess-core/codex/process",
        version: "1.0.0",
        owner_repo: "cli_subprocess_core",
        route_kind: "provider_runtime_profile",
        protocol_surface: "process",
        matcher_class: "deterministic_over_input",
        status_or_exit_or_response_or_stream_or_chunk_or_fault_shape: %{
          "status" => "configured",
          "raw_payload_shape" => ["configured"]
        },
        no_egress_assertion: %{
          "external_egress" => "deny",
          "process_spawn" => "deny",
          "side_effect_result" => "not_attempted"
        },
        bounded_evidence_projection: %{
          "contract_version" => "ExecutionPlane.LowerSimulationEvidence.v1",
          "raw_payload_persistence" => "shape_only",
          "fingerprints" => ["input", "output"]
        },
        input_fingerprint_ref: "fingerprint://cli_subprocess_core/phase6/input",
        cleanup_behavior: %{
          "runtime_artifacts" => "delete",
          "durable_payload" => "deny_raw"
        }
      }
    ]
  end
end
