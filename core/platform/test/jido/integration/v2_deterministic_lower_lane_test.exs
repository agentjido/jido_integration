defmodule Jido.Integration.V2DeterministicLowerLaneTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.DeterministicLowerLane
  alias Jido.Integration.V2.GovernedLowerEnvelope

  test "returns governed deterministic Codex, Linear publication, and GitHub receipt facts" do
    envelope = governed_lower_envelope()

    assert {:ok, result} =
             DeterministicLowerLane.invoke(
               "codex.session.turn",
               %{prompt: "prove deterministic lower lane"},
               governed_lower_envelope: envelope
             )

    assert result.run.run_id =~ "jido-run://"
    assert result.attempt.attempt_id =~ "/deterministic:1"

    receipt = result.output.governed_lower_receipt
    facts = result.output.deterministic_lower

    assert receipt["status"] == "succeeded"
    assert receipt["lower_runtime_kind"] == "codex_session"
    assert receipt["capability_id"] == "codex.session.turn"
    assert facts.status == "succeeded"
    assert facts.source_publication["capability_id"] == "linear.comments.update"
    assert facts.github_pr_evidence["provider"] == "github"

    event_kinds = Enum.map(facts.runtime_events, & &1["event_kind"])

    for event_kind <- [
          "codex.approval.required",
          "codex.approval.auto_approved",
          "codex.input.required",
          "codex.tool.unsupported",
          "codex.tool_input.auto_answered",
          "codex.dynamic_tool.completed",
          "codex.dynamic_tool.failed",
          "codex.dynamic_tool.unsupported",
          "codex.json.malformed",
          "codex.diagnostic.non_json",
          "codex.token.usage",
          "codex.rate_limit.observed",
          "codex.timeout",
          "codex.cancelled",
          "codex.app_server.shutdown",
          "codex.session.completed"
        ] do
      assert event_kind in event_kinds
    end
  end

  defp governed_lower_envelope do
    GovernedLowerEnvelope.new!(%{
      lower_request_ref: "lower-request://phase6/codex-turn",
      lower_runtime_kind: :codex_session,
      runtime_profile_ref: "runtime-profile://phase6/codex",
      runtime_profile_kind: :temporal_local,
      capability_id: "codex.session.turn",
      action_id: "codex.session.turn",
      tenant_ref: "tenant://phase6",
      subject_ref: "subject://phase6",
      run_ref: "run://phase6",
      workflow_ref: "workflow://phase6",
      trace_id: "trace-phase6",
      idempotency_key: "idem://phase6",
      authority_ref: "authority://phase6",
      authority_decision_hash: "sha256:" <> String.duplicate("1", 64),
      allowed_operations: ["codex.session.turn", "linear.comments.update"],
      connector_ref: "jido/connectors/codex_cli",
      connector_manifest_ref: "manifest://codex-cli@phase6",
      connector_manifest_hash: "sha256:" <> String.duplicate("2", 64),
      connector_manifest_state: :active,
      capability_negotiation_ref: "cap-neg://phase6/codex-turn",
      policy_bundle_ref: "policy-bundle://phase6/default",
      policy_bundle_hash: "sha256:" <> String.duplicate("3", 64),
      cedar_schema_ref: "cedar-schema://phase6/default",
      cedar_schema_hash: "sha256:" <> String.duplicate("4", 64),
      script_ref: "script://phase6/codex-turn",
      script_hash: "sha256:" <> String.duplicate("5", 64),
      package_refs: ["package://phase6/extravaganza"],
      resource_scope_refs: ["workspace://phase6"],
      workspace_ref: "workspace://phase6",
      target_ref: "target://phase6",
      sandbox_profile_ref: "sandbox://phase6/strict",
      sandbox_level: :strict,
      acceptable_attestation: ["attestation://phase6/deterministic"],
      attestation_requirement_ref: "attestation://phase6/deterministic",
      evidence_profile_ref: "evidence://phase6/github-pr-plus-workpad",
      redaction_profile_ref: "redaction://phase6/default",
      input_ref: "input://phase6/codex-turn",
      input_hash: "sha256:" <> String.duplicate("6", 64)
    })
  end
end
