defmodule Jido.Integration.V2.ServiceSimulationProfileTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ServiceSimulationProfile

  @required_fields [
    :profile_id,
    :version,
    :owner_repo,
    :environment_scope,
    :workload_ref,
    :pack_ref,
    :work_class_ref,
    :subject_kind,
    :tenant_policy_ref,
    :authority_policy_ref,
    :authorization_scope_requirements,
    :provider_refs,
    :model_refs,
    :endpoint_refs,
    :budget_profile_ref,
    :meter_profile_ref,
    :lower_scenario_refs,
    :no_egress_policy_ref,
    :evidence_policy_ref,
    :raw_body_policy,
    :input_fingerprint_policy,
    :cleanup_policy,
    :owner_evidence_refs
  ]

  test "materializes all required catalog fields as durable struct fields" do
    struct_fields =
      ServiceSimulationProfile.__struct__()
      |> Map.from_struct()
      |> Map.keys()

    assert Enum.all?(@required_fields, &(&1 in struct_fields))
  end

  test "round-trips the Jido-owned service profile through a json-safe dump map" do
    profile = ServiceSimulationProfile.new!(profile_attrs())
    dump = ServiceSimulationProfile.dump(profile)

    assert profile.contract_version == "ServiceSimulationProfile.v1"
    assert profile.owner_repo == "jido_integration"
    assert profile.version == "1.0.0"
    assert profile.provider_refs == ["provider://phase6/local-llama"]
    assert profile.lower_scenario_refs == ["lower-scenario://cli-subprocess/phase6/stream-text"]
    assert dump["contract_version"] == "ServiceSimulationProfile.v1"
    assert dump["owner_repo"] == "jido_integration"
    assert dump["raw_body_policy"]["raw_prompts"] == "deny"
    assert_json_safe(dump)
    assert ServiceSimulationProfile.new!(dump) == profile
  end

  test "rejects non-Jido ownership, including Execution Plane and StackLab" do
    for owner <- ["execution_plane", "stack_lab"] do
      assert_raise ArgumentError, ~r/owner_repo.*jido_integration/, fn ->
        ServiceSimulationProfile.new!(profile_attrs(%{owner_repo: owner}))
      end
    end
  end

  test "rejects public request simulation selectors" do
    assert_raise ArgumentError, ~r/public simulation selector/i, fn ->
      ServiceSimulationProfile.new!(Map.put(profile_attrs(), :simulation, "service_mode"))
    end
  end

  test "rejects missing lower scenario refs" do
    assert_raise ArgumentError, ~r/lower_scenario_refs.*must not be empty/, fn ->
      ServiceSimulationProfile.new!(profile_attrs(%{lower_scenario_refs: []}))
    end
  end

  test "rejects no-egress policies that allow real provider fallback" do
    assert_raise ArgumentError, ~r/no_egress_policy_ref.*forbids real provider egress/i, fn ->
      ServiceSimulationProfile.new!(
        profile_attrs(%{no_egress_policy_ref: "no-egress-policy://phase6/allow-real-provider"})
      )
    end
  end

  test "rejects durable raw prompt or provider body persistence" do
    assert_raise ArgumentError, ~r/raw_body_policy.*raw_prompts.*deny/, fn ->
      raw_body_policy =
        profile_attrs()
        |> Map.fetch!(:raw_body_policy)
        |> Map.put("raw_prompts", "allow")

      ServiceSimulationProfile.new!(profile_attrs(%{raw_body_policy: raw_body_policy}))
    end

    assert_raise ArgumentError, ~r/input_fingerprint_policy.*persist_raw_body/, fn ->
      input_fingerprint_policy =
        profile_attrs()
        |> Map.fetch!(:input_fingerprint_policy)
        |> Map.put("persist_raw_body?", true)

      ServiceSimulationProfile.new!(
        profile_attrs(%{input_fingerprint_policy: input_fingerprint_policy})
      )
    end
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
        lower_scenario_refs: ["lower-scenario://cli-subprocess/phase6/stream-text"],
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
