defmodule Jido.Integration.V2.DurableSubmissionContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthorityAuditEnvelope
  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.ExecutionGovernanceProjection
  alias Jido.Integration.V2.ExecutionGovernanceProjection.Compiler
  alias Jido.Integration.V2.ExecutionGovernanceProjection.Verifier
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionIdentity
  alias Jido.Integration.V2.SubmissionRejection

  test "submission keys stay stable across retries and change on redecision" do
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

    retried_identity = SubmissionIdentity.new!(SubmissionIdentity.dump(identity))

    redecision_identity =
      SubmissionIdentity.new!(%{
        SubmissionIdentity.dump(identity)
        | invocation_request_id: "invoke-2",
          authority_decision_id: "decision-2",
          execution_governance_id: "governance-2"
      })

    assert SubmissionIdentity.submission_key(identity) ==
             SubmissionIdentity.submission_key(retried_identity)

    refute SubmissionIdentity.submission_key(identity) ==
             SubmissionIdentity.submission_key(redecision_identity)
  end

  test "governance compiler and verifier freeze the shadow sections" do
    projection = execution_governance_projection()
    shadows = Compiler.compile!(projection)

    assert shadows.gateway_request == %{
             "allowed_operations" => ["shell.exec"],
             "sandbox" => %{
               "allowed_tools" => ["bash", "git"],
               "approvals" => :manual,
               "egress" => :restricted,
               "file_scope_hint" => "/srv/workspaces/tenant-1",
               "file_scope_ref" => "workspace://tenant-1/root",
               "level" => :strict
             }
           }

    assert shadows.runtime_request == %{
             "allowed_tools" => ["bash", "git"],
             "execution_family" => "process",
             "logical_workspace_ref" => "workspace://tenant-1/root",
             "placement_intent" => "host_local",
             "routing_hints" => %{
               "runtime_driver" => "asm",
               "runtime_provider" => "codex"
             },
             "target_kind" => "cli"
           }

    assert shadows.boundary_request == %{
             "boundary_class" => "hazmat",
             "requested_attach_mode" => "attach_if_exists",
             "requested_ttl_ms" => 60_000,
             "session_mode" => "attached"
           }

    assert :ok =
             Verifier.verify!(
               projection,
               shadows.gateway_request,
               shadows.runtime_request,
               shadows.boundary_request
             )

    assert {:error, :projection_mismatch, _details} =
             Verifier.verify(
               projection,
               put_in(shadows.gateway_request["sandbox"]["level"], :none),
               shadows.runtime_request,
               shadows.boundary_request
             )
  end

  test "brain invocation normalizes payload hashes and submission key" do
    identity = submission_identity_fixture()
    authority_payload = authority_audit_envelope()
    governance_payload = execution_governance_projection()
    shadows = Compiler.compile!(governance_payload)

    invocation =
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

    assert invocation.submission_key == SubmissionIdentity.submission_key(identity)

    assert invocation.authority_payload_hash ==
             AuthorityAuditEnvelope.payload_hash(authority_payload)

    assert invocation.execution_governance_payload_hash ==
             ExecutionGovernanceProjection.payload_hash(governance_payload)
  end

  test "submission result contracts stay explicit" do
    acceptance =
      SubmissionAcceptance.new!(%{
        submission_key: "sha256:" <> String.duplicate("a", 64),
        submission_receipt_ref: "receipt://submission/1",
        status: :accepted,
        ledger_version: 1
      })

    rejection =
      SubmissionRejection.new!(%{
        submission_key: "sha256:" <> String.duplicate("b", 64),
        rejection_family: :scope_unresolvable,
        reason_code: "workspace_ref_unresolved",
        retry_class: :after_redecision,
        redecision_required: true,
        details: %{"logical_workspace_ref" => "workspace://tenant-1/root"}
      })

    assert acceptance.status == :accepted
    assert rejection.retry_class == :after_redecision
    assert rejection.redecision_required
  end

  test "submission contracts accept canonical enum strings" do
    acceptance =
      SubmissionAcceptance.new!(%{
        submission_key: "sha256:" <> String.duplicate("c", 64),
        submission_receipt_ref: "receipt://submission/2",
        status: "duplicate",
        ledger_version: 2
      })

    identity =
      SubmissionIdentity.new!(%{
        submission_family: "boundary",
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

    rejection =
      SubmissionRejection.new!(%{
        submission_key: "sha256:" <> String.duplicate("d", 64),
        rejection_family: "policy_denied",
        reason_code: "approval_missing",
        retry_class: "retryable",
        details: %{"missing_approval" => true}
      })

    assert acceptance.status == :duplicate
    assert identity.submission_family == :boundary
    assert rejection.rejection_family == :policy_denied
    assert rejection.retry_class == :retryable
  end

  defp submission_identity_fixture do
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
  end

  defp authority_audit_envelope do
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
  end

  defp execution_governance_projection do
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
        "allowed_tools" => ["bash", "git"],
        "file_scope_ref" => "workspace://tenant-1/root",
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
        "logical_workspace_ref" => "workspace://tenant-1/root",
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
  end
end
