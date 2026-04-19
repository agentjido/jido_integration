defmodule Jido.Integration.V2.LowerTruthIntegrityContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ClaimCheckLifecycle
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.LowerEventPosition

  @checksum "sha256:#{String.duplicate("a", 64)}"

  test "lower event position accepts deterministic append evidence" do
    evidence =
      LowerEventPosition.new!(%{
        tenant_ref: "tenant:acme",
        installation_ref: "installation:acme",
        workspace_ref: "workspace:core",
        project_ref: "project:ops",
        environment_ref: "env:prod",
        principal_ref: "principal:operator-1",
        resource_ref: "lower-stream:run-123",
        authority_packet_ref: "authority-packet:123",
        permission_decision_ref: "decision:allow-123",
        idempotency_key: "idem:run-123:1",
        trace_id: "trace:phase4:m5:050",
        correlation_id: "corr:phase4:m5:050",
        release_manifest_ref: "phase4-v6-milestone5",
        lower_stream_ref: "lower-stream:run-123",
        lower_scope_ref: "lower-scope:tenant:acme",
        event_ref: "event:run-123:1",
        expected_position: 7,
        actual_position: 7,
        dedupe_key: "dedupe:run-123:1",
        position_status: "accepted",
        metadata: %{"source" => "test"}
      })

    assert evidence.contract_name == "JidoIntegration.LowerEventPosition.v1"
    assert evidence.position_status == :accepted
    assert LowerEventPosition.dump(evidence).actual_position == 7
  end

  test "lower event position records explicit conflict evidence" do
    evidence =
      LowerEventPosition.new!(%{
        tenant_ref: "tenant:acme",
        installation_ref: "installation:acme",
        workspace_ref: "workspace:core",
        project_ref: "project:ops",
        environment_ref: "env:prod",
        system_actor_ref: "system:jido-lower-store",
        resource_ref: "lower-stream:run-123",
        authority_packet_ref: "authority-packet:123",
        permission_decision_ref: "decision:allow-123",
        idempotency_key: "idem:run-123:2",
        trace_id: "trace:phase4:m5:050",
        correlation_id: "corr:phase4:m5:050",
        release_manifest_ref: "phase4-v6-milestone5",
        lower_stream_ref: "lower-stream:run-123",
        lower_scope_ref: "lower-scope:tenant:acme",
        event_ref: "event:run-123:2",
        expected_position: 7,
        actual_position: 8,
        dedupe_key: "dedupe:run-123:2",
        position_status: :conflict,
        conflict_ref: "conflict:lower-stream:run-123:7"
      })

    assert evidence.position_status == :conflict
    assert evidence.conflict_ref == "conflict:lower-stream:run-123:7"
  end

  test "lower event position fails closed on missing actor and invalid conflict shape" do
    assert {:error, %ArgumentError{message: message}} =
             LowerEventPosition.new(%{
               base_lower_event_position()
               | principal_ref: nil,
                 system_actor_ref: nil
             })

    assert message =~ "requires principal_ref or system_actor_ref"

    assert {:error, %ArgumentError{message: message}} =
             LowerEventPosition.new(%{
               base_lower_event_position()
               | position_status: :conflict,
                 actual_position: 9,
                 conflict_ref: nil
             })

    assert message =~ "conflict_ref is required"
  end

  test "lower event position rejects string-keyed contract drift" do
    attrs =
      base_lower_event_position()
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
      |> Map.put("contract_name", "JidoIntegration.LegacyLowerEventPosition.v0")

    assert {:error, %ArgumentError{message: message}} = LowerEventPosition.new(attrs)
    assert message =~ "lower_event_position.contract_name"
  end

  test "claim check lifecycle accepts quarantine evidence" do
    evidence =
      ClaimCheckLifecycle.new!(%{
        tenant_ref: "tenant:acme",
        installation_ref: "installation:acme",
        workspace_ref: "workspace:core",
        project_ref: "project:ops",
        environment_ref: "env:prod",
        system_actor_ref: "system:jido-claim-check",
        resource_ref: "claim-check:semantic-eval-1",
        authority_packet_ref: "authority-packet:456",
        permission_decision_ref: "decision:allow-456",
        idempotency_key: "idem:claim-check:semantic-eval-1",
        trace_id: "trace:phase4:m5:051",
        correlation_id: "corr:phase4:m5:051",
        release_manifest_ref: "phase4-v6-milestone5",
        claim_check_ref: "claim-check:semantic-eval-1",
        payload_hash: @checksum,
        schema_ref: "schema:OuterBrain.SemanticEvaluation.v1",
        size_bytes: 2048,
        retention_class: "workflow_run",
        lifecycle_state: "quarantined",
        quarantine_reason: "schema_invalid",
        gc_after_at: "2026-04-19T00:00:00Z",
        metadata: %{"quarantine_ref" => "quarantine:semantic-eval-1"}
      })

    assert evidence.contract_name == "JidoIntegration.ClaimCheckLifecycle.v1"
    assert evidence.lifecycle_state == :quarantined
    assert evidence.quarantine_reason == :schema_invalid
    assert %DateTime{} = evidence.gc_after_at
  end

  test "claim check lifecycle fails closed on quarantine and checksum drift" do
    assert {:error, %ArgumentError{message: message}} =
             ClaimCheckLifecycle.new(%{
               base_claim_check_lifecycle()
               | lifecycle_state: :quarantined,
                 quarantine_reason: nil
             })

    assert message =~ "quarantine_reason is required"

    assert {:error, %ArgumentError{message: message}} =
             ClaimCheckLifecycle.new(%{base_claim_check_lifecycle() | payload_hash: "bad"})

    assert message =~ "sha256"
  end

  test "claim check lifecycle rejects string-keyed contract drift" do
    attrs =
      base_claim_check_lifecycle()
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
      |> Map.put("contract_version", "0.0.0")

    assert {:error, %ArgumentError{message: message}} = ClaimCheckLifecycle.new(attrs)
    assert message =~ "claim_check_lifecycle.contract_version"
  end

  test "contracts facade names lower truth integrity contracts" do
    assert "JidoIntegration.LowerEventPosition.v1" in Contracts.lower_truth_integrity_contracts()

    assert "JidoIntegration.ClaimCheckLifecycle.v1" in Contracts.lower_truth_integrity_contracts()
  end

  defp base_lower_event_position do
    %{
      tenant_ref: "tenant:acme",
      installation_ref: "installation:acme",
      workspace_ref: "workspace:core",
      project_ref: "project:ops",
      environment_ref: "env:prod",
      principal_ref: "principal:operator-1",
      system_actor_ref: nil,
      resource_ref: "lower-stream:run-123",
      authority_packet_ref: "authority-packet:123",
      permission_decision_ref: "decision:allow-123",
      idempotency_key: "idem:run-123:1",
      trace_id: "trace:phase4:m5:050",
      correlation_id: "corr:phase4:m5:050",
      release_manifest_ref: "phase4-v6-milestone5",
      lower_stream_ref: "lower-stream:run-123",
      lower_scope_ref: "lower-scope:tenant:acme",
      event_ref: "event:run-123:1",
      expected_position: 7,
      actual_position: 7,
      dedupe_key: "dedupe:run-123:1",
      position_status: :accepted,
      conflict_ref: nil,
      metadata: %{}
    }
  end

  defp base_claim_check_lifecycle do
    %{
      tenant_ref: "tenant:acme",
      installation_ref: "installation:acme",
      workspace_ref: "workspace:core",
      project_ref: "project:ops",
      environment_ref: "env:prod",
      principal_ref: nil,
      system_actor_ref: "system:jido-claim-check",
      resource_ref: "claim-check:semantic-eval-1",
      authority_packet_ref: "authority-packet:456",
      permission_decision_ref: "decision:allow-456",
      idempotency_key: "idem:claim-check:semantic-eval-1",
      trace_id: "trace:phase4:m5:051",
      correlation_id: "corr:phase4:m5:051",
      release_manifest_ref: "phase4-v6-milestone5",
      claim_check_ref: "claim-check:semantic-eval-1",
      payload_hash: @checksum,
      schema_ref: "schema:OuterBrain.SemanticEvaluation.v1",
      size_bytes: 2048,
      retention_class: :workflow_run,
      lifecycle_state: :active,
      quarantine_reason: nil,
      gc_after_at: "2026-04-19T00:00:00Z",
      metadata: %{}
    }
  end
end
