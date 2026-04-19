defmodule Jido.Integration.V2.LowerSubmissionActivityTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.LowerSubmissionActivity

  test "declares tenant plus submission key as the retry idempotency scope" do
    assert LowerSubmissionActivity.contract_name() == "JidoIntegration.LowerSubmissionActivity.v1"
    assert LowerSubmissionActivity.idempotency_scope() == "tenant_ref + submission_dedupe_key"

    assert {:ok, activity} = LowerSubmissionActivity.new(activity_attrs())
    assert activity.contract_name == "JidoIntegration.LowerSubmissionActivity.v1"
    assert LowerSubmissionActivity.dedupe_key(activity) == {"tenant-alpha", "dedupe-099"}

    assert LowerSubmissionActivity.to_ledger_lookup(activity) == %{
             tenant_id: "tenant-alpha",
             submission_dedupe_key: "dedupe-099"
           }
  end

  test "duplicate Temporal activity retries keep the same durable lower submission scope" do
    assert {:ok, first} = LowerSubmissionActivity.new(activity_attrs())

    assert {:ok, retry} =
             LowerSubmissionActivity.new(
               activity_attrs(%{
                 activity_call_ref: "activity://workflow-099/lower/retry-1",
                 trace_id: "trace-099-retry"
               })
             )

    assert LowerSubmissionActivity.same_retry_scope?(first, retry)

    assert {:ok, different_tenant} =
             LowerSubmissionActivity.new(activity_attrs(%{tenant_ref: "tenant-beta"}))

    refute LowerSubmissionActivity.same_retry_scope?(first, different_tenant)
  end

  test "rejects missing actor, idempotency, lease evidence, and lower scope metadata" do
    assert {:error, {:missing_one_of, [:principal_ref, :system_actor_ref]}} =
             activity_attrs()
             |> Map.delete(:principal_ref)
             |> LowerSubmissionActivity.new()

    assert {:error, {:missing_required_fields, missing}} =
             activity_attrs()
             |> Map.drop([:idempotency_key, :lower_scope_ref, :lease_ref])
             |> LowerSubmissionActivity.new()

    assert :idempotency_key in missing
    assert :lower_scope_ref in missing
    assert :lease_ref in missing
  end

  defp activity_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        tenant_ref: "tenant-alpha",
        principal_ref: "principal-operator",
        resource_ref: "lower-submission:099",
        workflow_ref: "workflow-099",
        activity_call_ref: "activity://workflow-099/lower",
        lower_submission_ref: "lower-submission-099",
        submission_dedupe_key: "dedupe-099",
        authority_packet_ref: "authpkt-099",
        permission_decision_ref: "decision-099",
        trace_id: "trace-099",
        idempotency_key: "idem-lower-099",
        lower_scope_ref: "lower-scope-099",
        lease_ref: "lease://lower-099",
        lease_evidence_ref: "evidence://lease/lower-099",
        payload_ref: "claim://lower-payload-099",
        payload_hash: "sha256:lower-payload-099",
        retry_policy: "safe_idempotent",
        timeout_policy: "bounded",
        heartbeat_policy: "not_required_for_submission_intake",
        release_manifest_ref: "phase4-v6-milestone29"
      },
      overrides
    )
  end
end
