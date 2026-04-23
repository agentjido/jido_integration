defmodule Jido.Integration.V2AuthorityTenantPropagationTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthorityTenantPropagation
  alias Jido.Integration.V2.LowerSubmissionActivity
  alias Jido.Integration.V2.TenantScope

  test "declares the Jido Integration owner surface for AuthorityTenantPropagation.v1" do
    contract = AuthorityTenantPropagation.contract()

    assert contract.id == "AuthorityTenantPropagation.v1"
    assert contract.owner == :jido_integration
    assert contract.consumes_owner_contract == "AuthorityTenantPropagation.v1"

    assert contract.required_owner_fields == [
             :tenant_ref,
             :authority_decision_ref,
             :authorization_scope_ref,
             :budget_ref,
             :no_bypass_scope_ref,
             :lineage_ref,
             :causation_ref,
             :idempotency_ref,
             :lower_facts_propagation_ref
           ]
  end

  test "proves propagated tenant scope reaches lower execution facts" do
    assert {:ok, evidence} =
             AuthorityTenantPropagation.lower_owner_evidence(AuthorityTenantPropagation.fixture())

    assert %TenantScope{} = evidence.tenant_scope
    assert evidence.tenant_scope.tenant_id == "tenant-phase6-m8"
    assert evidence.tenant_scope.installation_id == "installation-phase6-m8"
    assert evidence.tenant_scope_ref == "tenant-scope://tenant-phase6-m8/run-phase6-m8"

    assert evidence.authorization_scope_ref ==
             "authorization-scope://tenant-phase6-m8/exec-phase6-m8"

    assert evidence.lineage_ref == "lineage://phase6/m8/exec-phase6-m8"

    assert %LowerSubmissionActivity{} = evidence.lower_submission_activity
    assert evidence.lower_submission_activity.tenant_ref == "tenant-phase6-m8"
    assert evidence.lower_submission_activity.lower_scope_ref == evidence.tenant_scope_ref
    assert evidence.lower_facts_operation == :resolve_trace

    assert evidence.lower_facts_result_ref ==
             "lower-facts-result://tenant-phase6-m8/run-phase6-m8"

    refute evidence.forbidden_present?
  end

  test "fails closed for missing authority, missing scope, budget, and no-bypass refs" do
    fixture = AuthorityTenantPropagation.fixture()

    assert {:error, :missing_authority_decision_ref} =
             fixture
             |> Map.put(:authority_decision_ref, nil)
             |> AuthorityTenantPropagation.lower_owner_evidence()

    assert {:error, :missing_authorization_scope_ref} =
             fixture
             |> Map.put(:authorization_scope_ref, "")
             |> AuthorityTenantPropagation.lower_owner_evidence()

    assert {:error, :missing_budget_ref} =
             fixture
             |> Map.delete(:budget_ref)
             |> AuthorityTenantPropagation.lower_owner_evidence()

    assert {:error, :missing_no_bypass_scope_ref} =
             fixture
             |> Map.delete(:no_bypass_scope_ref)
             |> AuthorityTenantPropagation.lower_owner_evidence()
  end

  test "rejects cross-tenant lower scope and lower facts mismatch" do
    fixture = AuthorityTenantPropagation.fixture()

    assert {:error, {:cross_tenant_scope, "tenant-other"}} =
             fixture
             |> put_in([:tenant_scope_attrs, :tenant_id], "tenant-other")
             |> AuthorityTenantPropagation.lower_owner_evidence()

    assert {:error, {:lower_facts_tenant_mismatch, "tenant-other"}} =
             fixture
             |> put_in([:lower_facts, :tenant_id], "tenant-other")
             |> AuthorityTenantPropagation.lower_owner_evidence()
  end

  test "rejects unsupported lower facts operations and direct lower shortcuts" do
    fixture = AuthorityTenantPropagation.fixture()

    assert {:error, {:unsupported_lower_facts_operation, :review_packet}} =
             fixture
             |> put_in([:lower_facts, :operation], :review_packet)
             |> AuthorityTenantPropagation.lower_owner_evidence()

    assert {:error, {:forbidden_evidence, :direct_lower_shortcut_bypassing_authority}} =
             fixture
             |> put_in([:lower_facts, :shortcut?], true)
             |> AuthorityTenantPropagation.lower_owner_evidence()
  end
end
