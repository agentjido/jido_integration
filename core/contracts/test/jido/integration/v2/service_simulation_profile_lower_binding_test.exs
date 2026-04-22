defmodule Jido.Integration.V2.ServiceSimulationProfileLowerBindingTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ServiceSimulationProfile
  alias Jido.Integration.V2.ServiceSimulationProfileLowerBinding

  @scenario_refs [
    "lower-scenario://execution-plane/http/success",
    "lower-scenario://cli-subprocess-core/codex/process",
    "lower-scenario://pristine/http/github-repos-get",
    "lower-scenario://prismatic/graphql/linear-issue-query",
    "lower-scenario://self-hosted-inference/backend/ready"
  ]

  test "binds every lower scenario ref against installed owner declarations at profile install" do
    profile = profile()
    binding = ServiceSimulationProfileLowerBinding.bind!(profile, installed_scenarios())
    dump = ServiceSimulationProfileLowerBinding.dump(binding)

    assert binding.profile_id == profile.profile_id
    assert binding.profile_version == profile.version
    assert binding.resolution_phase == :profile_install
    assert binding.lower_scenario_refs == @scenario_refs
    assert Enum.map(binding.resolved_lower_scenarios, & &1["scenario_id"]) == @scenario_refs

    assert binding.owner_repos == [
             "execution_plane",
             "cli_subprocess_core",
             "pristine",
             "prismatic",
             "self_hosted_inference_core"
           ]

    assert binding.protocol_surfaces == ["http", "process", "graphql", "self_hosted"]
    assert dump["resolution_phase"] == "profile_install"

    assert dump["resolved_lower_scenarios"] |> hd() |> Map.fetch!("contract_version") ==
             "ExecutionPlane.LowerSimulationScenario.v1"

    assert_json_safe(dump)
  end

  test "fails closed when a profile lower scenario ref has no installed declaration" do
    assert_raise ArgumentError, ~r/dangling lower_scenario_ref.*missing/, fn ->
      @scenario_refs
      |> List.replace_at(0, "lower-scenario://missing/owner/declaration")
      |> profile()
      |> ServiceSimulationProfileLowerBinding.bind!(installed_scenarios())
    end
  end

  test "fails closed on unsupported lower owner declarations" do
    bad_scenarios = [
      scenario_attrs("lower-scenario://stack-lab/not-an-owner", "stack_lab", "http")
    ]

    assert_raise ArgumentError, ~r/owner_repo.*lower scenario owner/, fn ->
      @scenario_refs
      |> List.replace_at(0, "lower-scenario://stack-lab/not-an-owner")
      |> profile()
      |> ServiceSimulationProfileLowerBinding.bind!(bad_scenarios)
    end
  end

  test "fails closed on egress, raw evidence, and raw payload narrowing violations" do
    assert_raise ArgumentError, ~r/no_egress_assertion.external_egress.*deny/, fn ->
      bad_scenarios =
        List.replace_at(
          installed_scenarios(),
          0,
          put_in(
            hd(installed_scenarios()),
            [:no_egress_assertion, "external_egress"],
            "allow"
          )
        )

      ServiceSimulationProfileLowerBinding.bind!(profile(), bad_scenarios)
    end

    assert_raise ArgumentError, ~r/raw_payload_persistence.*shape_only/, fn ->
      bad_scenarios =
        List.replace_at(
          installed_scenarios(),
          1,
          put_in(
            Enum.at(installed_scenarios(), 1),
            [:bounded_evidence_projection, "raw_payload_persistence"],
            "raw_body"
          )
        )

      ServiceSimulationProfileLowerBinding.bind!(profile(), bad_scenarios)
    end

    assert_raise ArgumentError, ~r/ExecutionOutcome.v1.raw_payload.*must not be narrowed/, fn ->
      bad_scenarios =
        List.replace_at(
          installed_scenarios(),
          2,
          put_in(
            Enum.at(installed_scenarios(), 2),
            [:bounded_evidence_projection, "target_contract"],
            "ExecutionOutcome.v1.raw_payload"
          )
        )

      ServiceSimulationProfileLowerBinding.bind!(profile(), bad_scenarios)
    end
  end

  test "rejects public simulation selectors and runtime dangling-ref resolution" do
    assert_raise ArgumentError, ~r/public simulation selector/i, fn ->
      ServiceSimulationProfileLowerBinding.bind!(profile(), installed_scenarios(),
        simulation: :service_mode
      )
    end

    assert_raise ArgumentError, ~r/runtime lower scenario resolution is forbidden/i, fn ->
      ServiceSimulationProfileLowerBinding.bind!(profile(), installed_scenarios(),
        resolution_phase: :runtime
      )
    end
  end

  defp profile(refs \\ @scenario_refs) do
    ServiceSimulationProfile.new!(profile_attrs(%{lower_scenario_refs: refs}))
  end

  defp installed_scenarios do
    [
      scenario_attrs("lower-scenario://execution-plane/http/success", "execution_plane", "http"),
      scenario_attrs(
        "lower-scenario://cli-subprocess-core/codex/process",
        "cli_subprocess_core",
        "process"
      ),
      scenario_attrs("lower-scenario://pristine/http/github-repos-get", "pristine", "http"),
      scenario_attrs(
        "lower-scenario://prismatic/graphql/linear-issue-query",
        "prismatic",
        "graphql"
      ),
      scenario_attrs(
        "lower-scenario://self-hosted-inference/backend/ready",
        "self_hosted_inference_core",
        "self_hosted"
      )
    ]
  end

  defp scenario_attrs(scenario_id, owner_repo, protocol_surface) do
    %{
      contract_version: "ExecutionPlane.LowerSimulationScenario.v1",
      scenario_id: scenario_id,
      version: "1.0.0",
      owner_repo: owner_repo,
      route_kind: route_kind(protocol_surface),
      protocol_surface: protocol_surface,
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
      input_fingerprint_ref: "fingerprint://#{owner_repo}/phase6/input",
      cleanup_behavior: %{
        "runtime_artifacts" => "delete",
        "durable_payload" => "deny_raw"
      }
    }
  end

  defp route_kind("process"), do: "provider_runtime_profile"
  defp route_kind("http"), do: "http_transport"
  defp route_kind("graphql"), do: "graphql_operation"
  defp route_kind("self_hosted"), do: "self_hosted_backend_manifest"

  defp profile_attrs(overrides) do
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
        lower_scenario_refs: @scenario_refs,
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
