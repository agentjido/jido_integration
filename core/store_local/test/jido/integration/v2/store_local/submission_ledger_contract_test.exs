defmodule Jido.Integration.V2.StoreLocal.SubmissionLedgerContractTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.AuthorityAuditEnvelope
  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.ExecutionGovernanceProjection
  alias Jido.Integration.V2.ExecutionGovernanceProjection.Compiler
  alias Jido.Integration.V2.StoreLocal.Storage
  alias Jido.Integration.V2.StoreLocal.SubmissionLedger
  alias Jido.Integration.V2.StoreLocal.TestSupport
  alias Jido.Integration.V2.SubmissionIdentity
  alias Jido.Integration.V2.SubmissionRejection

  setup do
    dir = TestSupport.tmp_dir!()
    :ok = TestSupport.reconfigure!(storage_dir: dir)
    :ok = TestSupport.reset_all!()

    on_exit(fn ->
      TestSupport.cleanup!(dir)
    end)

    %{storage_dir: dir}
  end

  test "accepts once and returns a duplicate after restart" do
    invocation = brain_invocation_fixture()

    assert {:ok, acceptance} = SubmissionLedger.accept_submission(invocation, [])
    assert acceptance.status == :accepted

    :ok = TestSupport.restart_store!()

    assert {:ok, duplicate} = SubmissionLedger.accept_submission(invocation, [])
    assert duplicate.status == :duplicate
    assert duplicate.submission_receipt_ref == acceptance.submission_receipt_ref

    assert {:accepted, looked_up} =
             SubmissionLedger.lookup_submission("dedupe-1", "tenant-1", [])

    assert looked_up.submission_key == invocation.submission_key
  end

  test "records typed rejections durably" do
    invocation = brain_invocation_fixture()

    rejection =
      SubmissionRejection.new!(%{
        submission_key: invocation.submission_key,
        rejection_family: :scope_unresolvable,
        reason_code: "workspace_ref_unresolved",
        retry_class: :after_redecision,
        redecision_required: true,
        details: %{"logical_workspace_ref" => "workspace://tenant-1/root"}
      })

    assert :ok = SubmissionLedger.record_rejection(invocation, rejection, [])

    assert %SubmissionRejection{} =
             Storage.read(fn state ->
               Map.fetch!(state.submission_rejections, invocation.submission_key)
             end)

    assert {:rejected, looked_up} =
             SubmissionLedger.lookup_submission("dedupe-1", "tenant-1", [])

    assert looked_up.reason_code == "workspace_ref_unresolved"
  end

  defp brain_invocation_fixture do
    identity =
      SubmissionIdentity.new!(%{
        submission_family: :invocation,
        tenant_id: "tenant-1",
        session_id: "session-1",
        request_id: "request-1",
        invocation_request_id: "invoke-1",
        causal_group_id: "cg-1",
        target_id: "target-1",
        target_kind: "cli",
        selected_step_id: "step-1",
        authority_decision_id: "decision-1",
        execution_governance_id: "governance-1",
        execution_intent_family: "process"
      })

    authority_payload =
      AuthorityAuditEnvelope.new!(%{
        contract_version: "v1",
        decision_id: "decision-1",
        tenant_id: "tenant-1",
        request_id: "request-1",
        policy_version: "policy-7",
        boundary_class: "hazmat",
        trust_profile: "trusted_operator",
        approval_profile: "manual",
        egress_profile: "restricted",
        workspace_profile: "workspace_attached",
        resource_profile: "balanced",
        decision_hash: String.duplicate("f", 64),
        extensions: %{}
      })

    governance_payload =
      ExecutionGovernanceProjection.new!(%{
        contract_version: "v1",
        execution_governance_id: "governance-1",
        authority_ref: %{
          "decision_id" => "decision-1",
          "policy_version" => "policy-7",
          "decision_hash" => String.duplicate("f", 64)
        },
        sandbox: %{
          "level" => "strict",
          "egress" => "restricted",
          "approvals" => "manual",
          "acceptable_attestation" => ["local-erlexec-weak"],
          "allowed_tools" => ["bash", "git"],
          "file_scope_ref" => "/srv/workspaces/tenant-1",
          "file_scope_hint" => "/srv/workspaces/tenant-1"
        },
        boundary: %{
          "boundary_class" => "hazmat",
          "trust_profile" => "trusted_operator",
          "requested_attach_mode" => "attach_if_exists",
          "requested_ttl_ms" => 60_000
        },
        topology: %{
          "topology_intent_id" => "topology-1",
          "session_mode" => "attached",
          "coordination_mode" => "single_target",
          "topology_epoch" => 9,
          "routing_hints" => %{
            "runtime_driver" => "asm",
            "runtime_provider" => "codex"
          }
        },
        workspace: %{
          "workspace_profile" => "workspace_attached",
          "logical_workspace_ref" => "/srv/workspaces/tenant-1",
          "mutability" => "read_write"
        },
        resources: %{
          "resource_profile" => "balanced",
          "cpu_class" => "medium",
          "memory_class" => "medium",
          "wall_clock_budget_ms" => 300_000
        },
        placement: %{
          "execution_family" => "process",
          "placement_intent" => "host_local",
          "target_kind" => "cli",
          "node_affinity" => "same_node"
        },
        operations: %{
          "allowed_operations" => ["shell.exec"],
          "effect_classes" => ["filesystem", "process"]
        },
        extensions: %{}
      })

    shadows = Compiler.compile!(governance_payload)

    BrainInvocation.new!(%{
      submission_identity: identity,
      request_id: "request-1",
      session_id: "session-1",
      tenant_id: "tenant-1",
      trace_id: "trace-1",
      actor_id: "actor-1",
      target_id: "target-1",
      target_kind: "cli",
      runtime_class: :direct,
      allowed_operations: ["shell.exec"],
      authority_payload: authority_payload,
      execution_governance_payload: governance_payload,
      gateway_request: shadows.gateway_request,
      runtime_request: shadows.runtime_request,
      boundary_request: shadows.boundary_request,
      execution_intent_family: "process",
      execution_intent: %{"argv" => ["echo", "hello"]},
      extensions: %{"submission_dedupe_key" => "dedupe-1"}
    })
  end
end
