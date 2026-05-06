defmodule Jido.ModelProviderRegistry.AdaptiveProofTest do
  use ExUnit.Case, async: true

  alias Jido.ModelProviderRegistry.AdaptiveProof

  test "live provider proof gates require green deterministic proofs and disposable refs" do
    assert {:error, {:missing_preceding_proofs, [:gepa, :trinity, :adaptive_control]}} =
             AdaptiveProof.live_provider_gate(%{})

    assert {:error, {:missing_disposable_refs, [:credential_lease_ref, :cleanup_ref]}} =
             live_provider_attrs()
             |> Map.drop([:credential_lease_ref, :cleanup_ref])
             |> AdaptiveProof.live_provider_gate()

    assert {:ok, receipt} = AdaptiveProof.live_provider_gate(live_provider_attrs())

    assert receipt.fixture_ref == "AOC-045"
    assert receipt.provider_account_ref == "provider-account://phase14/openai/disposable"
    assert receipt.model_profile_ref == "model-profile://phase14/openai/proposer"
    assert receipt.live_network_required? == false
    assert receipt.raw_material_present? == false
    refute Map.has_key?(receipt, :api_key)
  end

  test "OpenAPI and GraphQL proof refs are governed and fully bound" do
    assert {:error, {:missing_openapi_usage_contexts, [:appkit_management_api]}} =
             openapi_attrs()
             |> Map.put(:usage_contexts, [:tool_task, :eval_dataset_loader, :generated_sdk])
             |> AdaptiveProof.openapi_operation()

    assert {:ok, openapi} = AdaptiveProof.openapi_operation(openapi_attrs())

    assert openapi.fixture_ref == "AOC-046"
    assert openapi.pristine_operation_ref == "pristine-operation://github/issues/list"
    assert openapi.connector_admission_ref == "connector-admission://tenant-1/github"

    assert openapi.usage_contexts == [
             :tool_task,
             :eval_dataset_loader,
             :generated_sdk,
             :appkit_management_api
           ]

    assert {:error, {:missing_graphql_bindings, [:subject_ref, :token_family_ref]}} =
             graphql_attrs()
             |> Map.drop([:subject_ref, :token_family_ref])
             |> AdaptiveProof.graphql_operation()

    assert {:ok, graphql} = AdaptiveProof.graphql_operation(graphql_attrs())

    assert graphql.fixture_ref == "AOC-047"
    assert graphql.operation_name == "Viewer"
    assert graphql.provider_account_ref == "provider-account://tenant-1/linear/api-token"
    assert graphql.workspace_ref == "workspace://tenant-1/product"
    assert graphql.token_family_ref == "token-family://tenant-1/linear/api-token"
    assert graphql.subject_ref == "subject://tenant-1/operator/ada"
  end

  test "durable persistence profiles fail closed and debug sidecar receipts stay redacted" do
    assert {:error, {:durable_profile_preflight_failed, [:migration_ref, :substrate_ref]}} =
             AdaptiveProof.persistence_profile(%{
               profile_id: :integration_postgres,
               store_category: :debug_capture,
               capture_level: :debug_redacted
             })

    assert {:ok, durable} =
             AdaptiveProof.persistence_profile(%{
               profile_id: :integration_postgres,
               store_category: :debug_capture,
               capture_level: :debug_redacted,
               substrate_ref: "postgres-substrate://phase14/integration",
               migration_ref: "migration://phase14/debug-capture",
               partition_ref: "partition://tenant-1/debug",
               retention_ref: "retention://tenant-1/debug",
               debug_tap_ref: "debug-tap://tenant-1/redacted"
             })

    assert durable.fixture_ref == "PERSIST-AOC-006"
    assert durable.selected_tier == :postgres
    assert durable.restart_safe? == true

    assert {:error, {:debug_sidecar_raw_material_rejected, [:raw_prompt]}} =
             AdaptiveProof.debug_sidecar(%{
               debug_tap_ref: "debug-tap://tenant-1/redacted",
               trace_ref: "trace://phase14/debug",
               facts: %{summary_ref: "summary://phase14/debug"},
               raw_prompt: "super-secret prompt"
             })

    assert {:ok, sidecar} =
             AdaptiveProof.debug_sidecar(%{
               debug_tap_ref: "debug-tap://tenant-1/redacted",
               trace_ref: "trace://phase14/debug",
               facts: %{
                 summary_ref: "summary://phase14/debug",
                 state_ref: "state://phase14/debug",
                 payload_hash_ref: "hash://phase14/debug"
               }
             })

    assert sidecar.fixture_ref == "PERSIST-AOC-007"
    assert sidecar.capture_level == :debug_redacted
    assert sidecar.raw_material_present? == false
    refute Map.has_key?(sidecar, :raw_prompt)
    refute inspect(sidecar) =~ "super-secret"
  end

  defp live_provider_attrs do
    %{
      gepa_proof_ref: "proof://phase6/gepa",
      gepa_status: :green,
      trinity_proof_ref: "proof://phase8/trinity",
      trinity_status: :green,
      adaptive_control_proof_ref: "proof://phase13/adaptive-control",
      adaptive_control_status: :green,
      tenant_ref: "tenant://tenant-1",
      authority_ref: "authority://tenant-1/provider/live",
      provider_account_ref: "provider-account://phase14/openai/disposable",
      model_profile_ref: "model-profile://phase14/openai/proposer",
      operation_policy_ref: "operation-policy://phase14/live-provider/propose",
      credential_lease_ref: "credential-lease://phase14/openai/disposable",
      cleanup_ref: "cleanup://phase14/openai/disposable",
      target_ref: "target://phase14/live-provider",
      trace_ref: "trace://phase14/live-provider"
    }
  end

  defp openapi_attrs do
    %{
      tenant_ref: "tenant://tenant-1",
      subject_ref: "subject://tenant-1/operator/ada",
      provider_account_ref: "provider-account://tenant-1/github/app",
      credential_lease_ref: "credential-lease://tenant-1/github/app",
      operation_policy_ref: "operation-policy://tenant-1/github/issues/list",
      pristine_operation_ref: "pristine-operation://github/issues/list",
      connector_admission_ref: "connector-admission://tenant-1/github",
      trace_ref: "trace://tenant-1/github/issues/list",
      redaction_ref: "redaction://tenant-1/github",
      usage_contexts: [:tool_task, :eval_dataset_loader, :generated_sdk, :appkit_management_api]
    }
  end

  defp graphql_attrs do
    %{
      tenant_ref: "tenant://tenant-1",
      subject_ref: "subject://tenant-1/operator/ada",
      provider_account_ref: "provider-account://tenant-1/linear/api-token",
      workspace_ref: "workspace://tenant-1/product",
      token_family_ref: "token-family://tenant-1/linear/api-token",
      credential_lease_ref: "credential-lease://tenant-1/linear/api-token",
      operation_policy_ref: "operation-policy://tenant-1/linear/viewer",
      prismatic_operation_ref: "prismatic-operation://linear/viewer",
      operation_name: "Viewer",
      trace_ref: "trace://tenant-1/linear/viewer",
      redaction_ref: "redaction://tenant-1/linear"
    }
  end
end
