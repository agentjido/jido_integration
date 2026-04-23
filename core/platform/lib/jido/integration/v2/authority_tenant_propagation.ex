defmodule Jido.Integration.V2.AuthorityTenantPropagation do
  @moduledoc """
  Jido Integration owner evidence for `AuthorityTenantPropagation.v1`.

  This surface proves that propagated authority and tenant facts reached the
  lower execution boundary as a real `TenantScope` and lower submission
  activity before bounded lower-facts reads are considered valid evidence.
  """

  alias Jido.Integration.V2.AuthorityAuditEnvelope
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.LowerFacts
  alias Jido.Integration.V2.LowerSubmissionActivity
  alias Jido.Integration.V2.TenantScope

  @contract_id "AuthorityTenantPropagation.v1"
  @tenant_id "tenant-phase6-m8"
  @installation_id "installation-phase6-m8"
  @run_id "run-phase6-m8"
  @trace_id "trace-phase6-m8"
  @authority_decision_ref "authority-decision:phase6-m8"
  @authorization_scope_ref "authorization-scope://tenant-phase6-m8/exec-phase6-m8"
  @tenant_scope_ref "tenant-scope://tenant-phase6-m8/run-phase6-m8"
  @budget_ref "budget://phase6/m8/local-no-spend"
  @no_bypass_scope_ref "no-bypass://phase6/m8/authority-tenant-budget"
  @lower_facts_propagation_ref "lower-facts://tenant-phase6-m8/run-phase6-m8"
  @lower_facts_result_ref "lower-facts-result://tenant-phase6-m8/run-phase6-m8"

  @required_owner_fields [
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

  @type evidence :: %{
          contract_id: String.t(),
          tenant_scope: TenantScope.t(),
          tenant_scope_ref: String.t(),
          lower_submission_activity: LowerSubmissionActivity.t(),
          authority_decision_ref: String.t(),
          authorization_scope_ref: String.t(),
          budget_ref: String.t(),
          no_bypass_scope_ref: String.t(),
          lower_facts_operation: LowerFacts.operation(),
          lower_facts_result_ref: String.t(),
          forbidden_present?: false
        }

  @spec contract() :: map()
  def contract do
    %{
      id: @contract_id,
      owner: :jido_integration,
      consumes_owner_contract: @contract_id,
      required_owner_fields: @required_owner_fields
    }
  end

  @spec fixture() :: map()
  def fixture do
    %{
      tenant_ref: @tenant_id,
      authority_decision_ref: @authority_decision_ref,
      authorization_scope_ref: @authorization_scope_ref,
      budget_ref: @budget_ref,
      no_bypass_scope_ref: @no_bypass_scope_ref,
      lineage_ref: "lineage://phase6/m8/#{@run_id}",
      causation_ref: "causation://phase6/m8/request-phase6-m8",
      idempotency_ref: "idempotency://phase6/m8/#{@tenant_id}/request-phase6-m8",
      lower_facts_propagation_ref: @lower_facts_propagation_ref,
      authority_audit:
        AuthorityAuditEnvelope.new!(%{
          contract_version: "v1",
          decision_id: @authority_decision_ref,
          tenant_id: @tenant_id,
          request_id: "request-phase6-m8",
          policy_version: "policy-phase6-m8",
          boundary_class: "hazmat",
          trust_profile: "trusted_operator",
          approval_profile: "manual",
          egress_profile: "restricted",
          workspace_profile: "workspace_attached",
          resource_profile: "bounded",
          decision_hash: String.duplicate("a", 64),
          extensions: %{
            "authorization_scope_ref" => @authorization_scope_ref,
            "budget_ref" => @budget_ref
          }
        }),
      tenant_scope_attrs: %{
        tenant_id: @tenant_id,
        installation_id: @installation_id,
        actor_ref: %{id: "actor-phase6-m8", kind: "system"},
        trace_id: @trace_id,
        authorized_at: ~U[2026-04-22 12:00:00Z]
      },
      lower_submission_activity_attrs: lower_submission_activity_attrs(),
      lower_facts: %{
        tenant_id: @tenant_id,
        installation_id: @installation_id,
        tenant_scope_ref: @tenant_scope_ref,
        operation: :resolve_trace,
        propagation_ref: @lower_facts_propagation_ref,
        result_ref: @lower_facts_result_ref,
        shortcut?: false
      }
    }
  end

  @spec lower_owner_evidence(map() | keyword()) :: {:ok, evidence()} | {:error, term()}
  def lower_owner_evidence(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    with {:ok, tenant_ref} <- required_ref(attrs, :tenant_ref),
         {:ok, authority_decision_ref} <- required_ref(attrs, :authority_decision_ref),
         {:ok, authorization_scope_ref} <- required_ref(attrs, :authorization_scope_ref),
         {:ok, budget_ref} <- required_ref(attrs, :budget_ref),
         {:ok, no_bypass_scope_ref} <- required_ref(attrs, :no_bypass_scope_ref),
         {:ok, lineage_ref} <- required_ref(attrs, :lineage_ref),
         {:ok, causation_ref} <- required_ref(attrs, :causation_ref),
         {:ok, idempotency_ref} <- required_ref(attrs, :idempotency_ref),
         {:ok, lower_facts_ref} <- required_ref(attrs, :lower_facts_propagation_ref),
         {:ok, tenant_scope} <- tenant_scope(attrs),
         :ok <- tenant_ref_matches_scope(tenant_ref, tenant_scope),
         :ok <- authorization_scope_matches_scope(authorization_scope_ref, tenant_scope),
         {:ok, authority_audit} <- authority_audit(attrs),
         :ok <-
           authority_audit_matches_scope(authority_audit, authority_decision_ref, tenant_scope),
         {:ok, lower_facts} <- lower_facts(attrs, tenant_scope, lower_facts_ref),
         {:ok, lower_activity} <- lower_submission_activity(attrs),
         :ok <-
           activity_matches_scope(
             lower_activity,
             tenant_scope,
             authority_decision_ref,
             lower_facts.tenant_scope_ref
           ) do
      {:ok,
       %{
         contract_id: @contract_id,
         tenant_scope: tenant_scope,
         tenant_scope_ref: lower_facts.tenant_scope_ref,
         lower_submission_activity: lower_activity,
         tenant_ref: tenant_ref,
         authority_decision_ref: authority_decision_ref,
         authorization_scope_ref: authorization_scope_ref,
         budget_ref: budget_ref,
         no_bypass_scope_ref: no_bypass_scope_ref,
         lineage_ref: lineage_ref,
         causation_ref: causation_ref,
         idempotency_ref: idempotency_ref,
         lower_facts_propagation_ref: lower_facts_ref,
         lower_facts_operation: lower_facts.operation,
         lower_facts_result_ref: lower_facts.result_ref,
         forbidden_present?: false
       }}
    end
  end

  def lower_owner_evidence(_attrs), do: {:error, :invalid_authority_tenant_attrs}

  defp lower_submission_activity_attrs do
    %{
      tenant_ref: @tenant_id,
      system_actor_ref: "system:jido-integration",
      resource_ref: "lower-resource://phase6/m8/#{@run_id}",
      workflow_ref: "workflow://phase6/m8/authority-tenant-propagation",
      activity_call_ref: "activity-call://phase6/m8/lower-submit",
      lower_submission_ref: "lower-submission://phase6/m8/#{@run_id}",
      submission_dedupe_key: "submission-dedupe://phase6/m8/#{@tenant_id}/request-phase6-m8",
      authority_packet_ref: "authority-packet://phase6/m8/request-phase6-m8",
      permission_decision_ref: @authority_decision_ref,
      trace_id: @trace_id,
      idempotency_key: "idempotency://phase6/m8/#{@tenant_id}/request-phase6-m8",
      lower_scope_ref: @tenant_scope_ref,
      lease_ref: "lease://phase6/m8/#{@tenant_id}",
      lease_evidence_ref: "lease-evidence://phase6/m8/#{@tenant_id}",
      payload_hash: "sha256:" <> String.duplicate("b", 64),
      retry_policy: %{max_attempts: 2, strategy: "fail_closed"},
      timeout_policy: %{start_to_close_ms: 30_000},
      heartbeat_policy: %{heartbeat_ms: 5_000},
      release_manifest_ref: "phase6-release-manifest://m8"
    }
  end

  defp tenant_scope(attrs) do
    case Contracts.get(attrs, :tenant_scope_attrs) do
      attrs when is_map(attrs) or is_list(attrs) -> TenantScope.new(attrs)
      _other -> {:error, :missing_tenant_scope}
    end
  end

  defp authority_audit(attrs) do
    case Contracts.get(attrs, :authority_audit) do
      %AuthorityAuditEnvelope{} = envelope -> AuthorityAuditEnvelope.new(envelope)
      attrs when is_map(attrs) or is_list(attrs) -> AuthorityAuditEnvelope.new(attrs)
      _other -> {:error, :missing_authority_audit}
    end
  end

  defp lower_submission_activity(attrs) do
    case Contracts.get(attrs, :lower_submission_activity_attrs) do
      attrs when is_map(attrs) or is_list(attrs) -> LowerSubmissionActivity.new(attrs)
      _other -> {:error, :missing_lower_submission_activity}
    end
  end

  defp lower_facts(attrs, %TenantScope{} = tenant_scope, lower_facts_ref) do
    case Contracts.get(attrs, :lower_facts) do
      lower_facts when is_map(lower_facts) ->
        validate_lower_facts(lower_facts, tenant_scope, lower_facts_ref)

      _other ->
        {:error, :missing_lower_facts_propagation_ref}
    end
  end

  defp validate_lower_facts(lower_facts, %TenantScope{} = tenant_scope, lower_facts_ref) do
    with :ok <- reject_direct_shortcut(lower_facts),
         {:ok, tenant_id} <- required_ref(lower_facts, :tenant_id),
         :ok <- lower_facts_tenant_matches(tenant_id, tenant_scope),
         :ok <- lower_facts_installation_matches(lower_facts, tenant_scope),
         {:ok, tenant_scope_ref} <- required_ref(lower_facts, :tenant_scope_ref),
         {:ok, propagation_ref} <- required_ref(lower_facts, :propagation_ref),
         :ok <- lower_facts_ref_matches(propagation_ref, lower_facts_ref),
         {:ok, operation} <- lower_facts_operation(lower_facts),
         {:ok, result_ref} <- required_ref(lower_facts, :result_ref) do
      {:ok,
       %{
         tenant_scope_ref: tenant_scope_ref,
         operation: operation,
         result_ref: result_ref
       }}
    end
  end

  defp reject_direct_shortcut(lower_facts) do
    if Contracts.get(lower_facts, :shortcut?) == true do
      {:error, {:forbidden_evidence, :direct_lower_shortcut_bypassing_authority}}
    else
      :ok
    end
  end

  defp lower_facts_tenant_matches(tenant_id, %TenantScope{} = tenant_scope) do
    if tenant_id == tenant_scope.tenant_id do
      :ok
    else
      {:error, {:lower_facts_tenant_mismatch, tenant_id}}
    end
  end

  defp lower_facts_installation_matches(lower_facts, %TenantScope{} = tenant_scope) do
    installation_id = Contracts.get(lower_facts, :installation_id)

    if tenant_scope.installation_id && installation_id &&
         installation_id != tenant_scope.installation_id do
      {:error, {:lower_facts_installation_mismatch, installation_id}}
    else
      :ok
    end
  end

  defp lower_facts_ref_matches(propagation_ref, lower_facts_ref) do
    if propagation_ref == lower_facts_ref do
      :ok
    else
      {:error, {:lower_facts_propagation_ref_mismatch, propagation_ref}}
    end
  end

  defp lower_facts_operation(lower_facts) do
    operation = Contracts.get(lower_facts, :operation)

    if is_atom(operation) && LowerFacts.operation_supported?(operation) do
      {:ok, operation}
    else
      {:error, {:unsupported_lower_facts_operation, operation}}
    end
  end

  defp tenant_ref_matches_scope(tenant_ref, %TenantScope{} = tenant_scope) do
    if tenant_ref == tenant_scope.tenant_id do
      :ok
    else
      {:error, {:cross_tenant_scope, tenant_scope.tenant_id}}
    end
  end

  defp authorization_scope_matches_scope(authorization_scope_ref, %TenantScope{} = tenant_scope) do
    expected_prefix = "authorization-scope://" <> tenant_scope.tenant_id <> "/"

    if String.starts_with?(authorization_scope_ref, expected_prefix) do
      :ok
    else
      {:error, {:cross_tenant_authorization_scope, authorization_scope_ref}}
    end
  end

  defp authority_audit_matches_scope(
         %AuthorityAuditEnvelope{} = authority_audit,
         authority_decision_ref,
         %TenantScope{} = tenant_scope
       ) do
    cond do
      authority_audit.decision_id != authority_decision_ref ->
        {:error, {:authority_decision_ref_mismatch, authority_audit.decision_id}}

      authority_audit.tenant_id != tenant_scope.tenant_id ->
        {:error, {:authority_audit_tenant_mismatch, authority_audit.tenant_id}}

      true ->
        :ok
    end
  end

  defp activity_matches_scope(
         %LowerSubmissionActivity{} = activity,
         %TenantScope{} = tenant_scope,
         authority_decision_ref,
         tenant_scope_ref
       ) do
    cond do
      activity.tenant_ref != tenant_scope.tenant_id ->
        {:error, {:lower_activity_tenant_mismatch, activity.tenant_ref}}

      activity.permission_decision_ref != authority_decision_ref ->
        {:error, {:permission_decision_ref_mismatch, activity.permission_decision_ref}}

      activity.lower_scope_ref != tenant_scope_ref ->
        {:error, {:lower_scope_ref_mismatch, activity.lower_scope_ref}}

      true ->
        :ok
    end
  end

  defp required_ref(attrs, :authority_decision_ref) do
    required_ref(attrs, :authority_decision_ref, :missing_authority_decision_ref)
  end

  defp required_ref(attrs, :authorization_scope_ref) do
    required_ref(attrs, :authorization_scope_ref, :missing_authorization_scope_ref)
  end

  defp required_ref(attrs, :budget_ref), do: required_ref(attrs, :budget_ref, :missing_budget_ref)

  defp required_ref(attrs, :no_bypass_scope_ref) do
    required_ref(attrs, :no_bypass_scope_ref, :missing_no_bypass_scope_ref)
  end

  defp required_ref(attrs, :lower_facts_propagation_ref) do
    required_ref(attrs, :lower_facts_propagation_ref, :missing_lower_facts_propagation_ref)
  end

  defp required_ref(attrs, field), do: required_ref(attrs, field, {:missing_required_ref, field})

  defp required_ref(attrs, field, error) do
    case Contracts.get(attrs, field) do
      ref when is_binary(ref) and ref != "" -> {:ok, ref}
      _other -> {:error, error}
    end
  end
end
