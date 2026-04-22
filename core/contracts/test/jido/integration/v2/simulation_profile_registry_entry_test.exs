defmodule Jido.Integration.V2.SimulationProfileRegistryEntryTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.SimulationProfileRegistryEntry

  @required_fields [
    :profile_id,
    :profile_version,
    :owner_refs,
    :environment_scope,
    :lower_scenario_refs,
    :no_egress_policy_ref,
    :audit_install_actor_ref,
    :audit_install_timestamp,
    :audit_update_history_refs,
    :audit_remove_actor_ref_or_null,
    :cleanup_status,
    :cleanup_artifact_refs,
    :owner_evidence_refs
  ]

  test "materializes catalog-required fields and dumps json-safe lifecycle evidence" do
    installed_at = ~U[2026-04-22 12:00:00Z]

    entry =
      SimulationProfileRegistryEntry.new!(%{
        profile_id: "service-profile://phase6/jido/local-llama",
        profile_version: "1.0.0",
        owner_refs: ["owner://jido_integration/service-profile"],
        environment_scope: "local_dev_no_egress",
        lower_scenario_refs: ["lower-scenario://cli-subprocess-core/codex/process"],
        no_egress_policy_ref: "no-egress-policy://phase6/block-provider-and-saas",
        audit_install_actor_ref: "actor://operator/install",
        audit_install_timestamp: installed_at,
        audit_update_history_refs: ["audit://profile/update/1"],
        cleanup_status: :active,
        cleanup_artifact_refs: [],
        owner_evidence_refs: ["owner-evidence://jido-integration/contracts/service-profile"]
      })

    struct_fields =
      SimulationProfileRegistryEntry.__struct__()
      |> Map.from_struct()
      |> Map.keys()

    assert Enum.all?(@required_fields, &(&1 in struct_fields))
    assert entry.contract_version == "SimulationProfileRegistryEntry.v1"
    assert entry.audit_remove_actor_ref_or_null == nil
    assert entry.audit_install_timestamp == installed_at

    dump = SimulationProfileRegistryEntry.dump(entry)
    assert dump["contract_version"] == "SimulationProfileRegistryEntry.v1"
    assert dump["audit_install_timestamp"] == DateTime.to_iso8601(installed_at)
    assert dump["cleanup_status"] == "active"
    assert_json_safe(dump)
    assert SimulationProfileRegistryEntry.new!(dump) == entry
  end

  test "builds install entries only after profile and lower scenario policy validation" do
    assert {:ok, entry} =
             SimulationProfileRegistryEntry.install(profile_attrs(), installed_scenarios(), %{
               owner_refs: ["owner://jido_integration/service-profile"],
               audit_install_actor_ref: "actor://operator/install",
               audit_install_timestamp: ~U[2026-04-22 12:00:00Z]
             })

    assert entry.profile_id == "service-profile://phase6/jido/local-llama"
    assert entry.profile_version == "1.0.0"
    assert entry.environment_scope == "local_dev_no_egress"
    assert entry.lower_scenario_refs == ["lower-scenario://cli-subprocess-core/codex/process"]

    assert {:error, :missing_owner} =
             SimulationProfileRegistryEntry.install(profile_attrs(), installed_scenarios(), %{
               owner_refs: [],
               audit_install_actor_ref: "actor://operator/install"
             })

    assert {:error, :missing_owner_evidence} =
             SimulationProfileRegistryEntry.install(
               profile_attrs(%{owner_evidence_refs: []}),
               installed_scenarios(),
               %{
                 owner_refs: ["owner://jido_integration/service-profile"],
                 audit_install_actor_ref: "actor://operator/install"
               }
             )

    assert {:error, :missing_no_egress_policy} =
             SimulationProfileRegistryEntry.install(
               profile_attrs(%{no_egress_policy_ref: "no-egress-policy://phase6/allow-real"}),
               installed_scenarios(),
               %{
                 owner_refs: ["owner://jido_integration/service-profile"],
                 audit_install_actor_ref: "actor://operator/install"
               }
             )

    assert {:error, :dangling_lower_scenario_ref} =
             SimulationProfileRegistryEntry.install(
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
             SimulationProfileRegistryEntry.install(
               profile_attrs(%{
                 raw_body_policy:
                   Map.put(profile_attrs().raw_body_policy, "raw_provider_bodies", "allow")
               }),
               installed_scenarios(),
               %{
                 owner_refs: ["owner://jido_integration/service-profile"],
                 audit_install_actor_ref: "actor://operator/install"
               }
             )
  end

  test "updates, selects, and removes entries with stale/environment/cleanup failures" do
    {:ok, entry} =
      SimulationProfileRegistryEntry.install(profile_attrs(), installed_scenarios(), %{
        owner_refs: ["owner://jido_integration/service-profile"],
        audit_install_actor_ref: "actor://operator/install"
      })

    assert {:error, :environment_mismatch} =
             SimulationProfileRegistryEntry.select(
               entry,
               "prod_real_provider",
               "owner://jido_integration/service-profile"
             )

    assert {:error, :missing_owner} =
             SimulationProfileRegistryEntry.select(
               entry,
               "local_dev_no_egress",
               "owner://execution_plane/lower"
             )

    assert {:error, :stale_version} =
             SimulationProfileRegistryEntry.update(
               entry,
               profile_attrs(%{version: "1.0.0"}),
               installed_scenarios(),
               %{audit_update_history_ref: "audit://profile/update/stale"}
             )

    assert {:ok, updated} =
             SimulationProfileRegistryEntry.update(
               entry,
               profile_attrs(%{version: "1.1.0"}),
               installed_scenarios(),
               %{audit_update_history_ref: "audit://profile/update/1"}
             )

    assert updated.profile_version == "1.1.0"
    assert updated.audit_update_history_refs == ["audit://profile/update/1"]

    assert {:error, :cleanup_failure} =
             SimulationProfileRegistryEntry.remove(updated, %{
               audit_remove_actor_ref: "actor://operator/remove",
               cleanup_status: :cleanup_failed,
               cleanup_artifact_refs: ["artifact://profile/temp"]
             })

    assert {:ok, removed} =
             SimulationProfileRegistryEntry.remove(updated, %{
               audit_remove_actor_ref: "actor://operator/remove",
               cleanup_artifact_refs: ["artifact://profile/temp"]
             })

    assert removed.cleanup_status == :removed
    assert removed.audit_remove_actor_ref_or_null == "actor://operator/remove"
    assert removed.owner_evidence_refs == updated.owner_evidence_refs
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

  defp assert_json_safe(value) when is_binary(value) or is_boolean(value) or is_nil(value),
    do: :ok

  defp assert_json_safe(value) when is_integer(value) or is_float(value), do: :ok

  defp assert_json_safe(value) when is_list(value) do
    Enum.each(value, &assert_json_safe/1)
  end

  defp assert_json_safe(value) when is_map(value) do
    assert Enum.all?(Map.keys(value), &is_binary/1)
    Enum.each(value, fn {_key, nested} -> assert_json_safe(nested) end)
  end
end
