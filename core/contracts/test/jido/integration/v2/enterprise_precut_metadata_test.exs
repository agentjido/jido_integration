defmodule Jido.Integration.V2.EnterprisePrecutMetadataTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.{
    ArtifactReadMetadata,
    ConnectorEffectMetadata,
    LowerEventMetadata,
    LowerIdempotency,
    LowerReadMetadata,
    LowerSubmissionMetadata,
    TargetDescriptorMetadata
  }

  @modules [
    LowerSubmissionMetadata,
    LowerReadMetadata,
    ArtifactReadMetadata,
    TargetDescriptorMetadata,
    ConnectorEffectMetadata,
    LowerIdempotency,
    LowerEventMetadata
  ]

  test "loads every M24 Jido Integration metadata contract" do
    for module <- @modules do
      assert Code.ensure_loaded?(module), "#{inspect(module)} is not compiled"
    end
  end

  test "lower submission metadata carries enterprise pre-cut scope" do
    assert {:ok, metadata} =
             LowerSubmissionMetadata.new(%{
               tenant_ref: "tenant-acme",
               principal_ref: "principal-operator",
               resource_ref: "resource-work-1",
               workflow_ref: "wf-110",
               activity_call_ref: "act-112",
               authority_packet_ref: "authpkt-112",
               permission_decision_ref: "decision-112",
               trace_id: "trace-112",
               idempotency_key: "idem-lower-112",
               dedupe_scope: "tenant-acme:target-1",
               target_ref: "target-1",
               connector_ref: "connector-1",
               installation_ref: "installation-1",
               activation_epoch: 1,
               payload_hash: String.duplicate("a", 64),
               payload_ref: "claim-lower-112"
             })

    assert metadata.contract_name == "JidoIntegration.LowerSubmissionMetadata.v1"
    assert metadata.permission_decision_ref == "decision-112"
  end

  test "lower read and artifact metadata fail closed without tenant or authority" do
    assert {:ok, _read} =
             LowerReadMetadata.new(%{
               tenant_ref: "tenant-acme",
               actor_ref: "principal-operator",
               resource_ref: "resource-work-1",
               lower_run_ref: "lower-113",
               permission_decision_ref: "decision-113",
               trace_id: "trace-113",
               redaction_posture: "operator_summary"
             })

    assert {:error, {:missing_required_fields, [:permission_decision_ref]}} =
             ArtifactReadMetadata.new(%{
               tenant_ref: "tenant-acme",
               actor_ref: "principal-operator",
               resource_ref: "resource-work-1",
               artifact_ref: "artifact-113",
               trace_id: "trace-113",
               redaction_posture: "operator_summary"
             })
  end

  test "connector effects and lower events carry revision, trace, and dedupe refs" do
    assert {:ok, _target} =
             TargetDescriptorMetadata.new(%{
               target_ref: "target-1",
               tenant_ref: "tenant-acme",
               resource_ref: "resource-work-1",
               runtime_family: "beam",
               trace_id: "trace-112"
             })

    assert {:ok, _effect} =
             ConnectorEffectMetadata.new(%{
               tenant_ref: "tenant-acme",
               connector_ref: "connector-1",
               installation_ref: "installation-1",
               activation_epoch: 1,
               authority_packet_ref: "authpkt-112",
               permission_decision_ref: "decision-112",
               trace_id: "trace-112",
               idempotency_key: "idem-effect-112",
               dedupe_scope: "tenant-acme:connector-1"
             })

    assert {:ok, _idempotency} =
             LowerIdempotency.new(%{
               tenant_ref: "tenant-acme",
               idempotency_key: "idem-lower-112",
               dedupe_scope: "tenant-acme:target-1",
               side_effect_ref: "lower-112",
               trace_id: "trace-112"
             })

    assert {:ok, _event} =
             LowerEventMetadata.new(%{
               lower_event_id: "lower-event-1",
               tenant_ref: "tenant-acme",
               resource_ref: "resource-work-1",
               lower_run_ref: "lower-112",
               workflow_ref: "wf-110",
               activity_call_ref: "act-112",
               trace_id: "trace-112",
               payload_hash: String.duplicate("b", 64)
             })
  end
end
