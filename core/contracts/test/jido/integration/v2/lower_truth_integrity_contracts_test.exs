defmodule Jido.Integration.V2.LowerTruthIntegrityContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ClaimCheckLifecycle
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.InstallationRevisionEpoch
  alias Jido.Integration.V2.LeaseRevocation
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

  test "installation revision epoch accepts current fence evidence" do
    evidence =
      InstallationRevisionEpoch.new!(%{
        tenant_ref: "tenant:acme",
        installation_ref: "installation:acme",
        workspace_ref: "workspace:core",
        project_ref: "project:ops",
        environment_ref: "env:prod",
        system_actor_ref: "system:jido-lower-store",
        resource_ref: "lease:read:run-123",
        authority_packet_ref: "authority-packet:789",
        permission_decision_ref: "decision:allow-789",
        idempotency_key: "idem:revision-epoch:run-123",
        trace_id: "trace:phase4:m10:063",
        correlation_id: "corr:phase4:m10:063",
        release_manifest_ref: "phase4-v6-milestone10",
        installation_revision: 42,
        activation_epoch: 7,
        lease_epoch: 5,
        node_id: "node:worker-a",
        fence_decision_ref: "fence:run-123:accepted",
        fence_status: "accepted",
        stale_reason: "none"
      })

    assert evidence.contract_name == "Platform.InstallationRevisionEpoch.v1"
    assert evidence.fence_status == :accepted
    assert InstallationRevisionEpoch.dump(evidence).installation_revision == 42
  end

  test "installation revision epoch fails closed on stale or inconsistent evidence" do
    assert {:error, %ArgumentError{message: message}} =
             InstallationRevisionEpoch.new(%{
               base_installation_revision_epoch()
               | fence_status: :accepted,
                 stale_reason: "installation_revision_stale",
                 attempted_installation_revision: 41
             })

    assert message =~ "accepted fences must use stale_reason none"

    assert {:error, %ArgumentError{message: message}} =
             InstallationRevisionEpoch.new(%{
               base_installation_revision_epoch()
               | fence_status: :rejected,
                 stale_reason: "none",
                 attempted_installation_revision: 41
             })

    assert message =~ "rejected fences require stale attempted evidence"

    assert {:error, %ArgumentError{message: message}} =
             InstallationRevisionEpoch.new(%{
               base_installation_revision_epoch()
               | principal_ref: nil,
                 system_actor_ref: nil
             })

    assert message =~ "requires principal_ref or system_actor_ref"
  end

  test "lease revocation accepts revocation propagation evidence" do
    evidence =
      LeaseRevocation.new!(%{
        tenant_ref: "tenant:acme",
        installation_ref: "installation:acme",
        workspace_ref: "workspace:core",
        project_ref: "project:ops",
        environment_ref: "env:prod",
        system_actor_ref: "system:jido-lower-store",
        resource_ref: "lease:stream:run-123",
        authority_packet_ref: "authority-packet:790",
        permission_decision_ref: "decision:allow-790",
        idempotency_key: "idem:lease-revocation:run-123",
        trace_id: "trace:phase4:m10:077",
        correlation_id: "corr:phase4:m10:077",
        release_manifest_ref: "phase4-v6-milestone10",
        lease_ref: "lease:stream:run-123",
        revocation_ref: "lease-revocation:stream:run-123:1",
        revoked_at: "2026-04-19T00:00:00Z",
        lease_scope: %{"tenant_ref" => "tenant:acme", "family" => "runtime_stream"},
        cache_invalidation_ref: "lease-cache-invalidation:stream:run-123:1",
        post_revocation_attempt_ref: "attempt:stream:run-123:after-revoke",
        lease_status: "rejected_after_revocation"
      })

    assert evidence.contract_name == "Platform.LeaseRevocation.v1"
    assert evidence.lease_status == :rejected_after_revocation
    assert %DateTime{} = evidence.revoked_at
  end

  test "lease revocation fails closed on actor and scope drift" do
    assert {:error, %ArgumentError{message: message}} =
             LeaseRevocation.new(%{
               base_lease_revocation()
               | principal_ref: nil,
                 system_actor_ref: nil
             })

    assert message =~ "requires principal_ref or system_actor_ref"

    assert {:error, %ArgumentError{message: message}} =
             LeaseRevocation.new(%{base_lease_revocation() | lease_scope: %{}})

    assert message =~ "non-empty JSON object"
  end

  test "contracts facade names lower truth integrity contracts" do
    assert "JidoIntegration.LowerEventPosition.v1" in Contracts.lower_truth_integrity_contracts()

    assert "JidoIntegration.ClaimCheckLifecycle.v1" in Contracts.lower_truth_integrity_contracts()

    assert "Platform.InstallationRevisionEpoch.v1" in Contracts.lower_truth_integrity_contracts()
    assert "Platform.LeaseRevocation.v1" in Contracts.lower_truth_integrity_contracts()
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

  defp base_installation_revision_epoch do
    %{
      tenant_ref: "tenant:acme",
      installation_ref: "installation:acme",
      workspace_ref: "workspace:core",
      project_ref: "project:ops",
      environment_ref: "env:prod",
      principal_ref: nil,
      system_actor_ref: "system:jido-lower-store",
      resource_ref: "lease:read:run-123",
      authority_packet_ref: "authority-packet:789",
      permission_decision_ref: "decision:allow-789",
      idempotency_key: "idem:revision-epoch:run-123",
      trace_id: "trace:phase4:m10:063",
      correlation_id: "corr:phase4:m10:063",
      release_manifest_ref: "phase4-v6-milestone10",
      installation_revision: 42,
      activation_epoch: 7,
      lease_epoch: 5,
      node_id: "node:worker-a",
      fence_decision_ref: "fence:run-123:accepted",
      fence_status: :accepted,
      stale_reason: "none",
      attempted_installation_revision: nil,
      attempted_activation_epoch: nil,
      attempted_lease_epoch: nil,
      mixed_revision_node_ref: nil,
      rollout_window_ref: nil
    }
  end

  defp base_lease_revocation do
    %{
      tenant_ref: "tenant:acme",
      installation_ref: "installation:acme",
      workspace_ref: "workspace:core",
      project_ref: "project:ops",
      environment_ref: "env:prod",
      principal_ref: nil,
      system_actor_ref: "system:jido-lower-store",
      resource_ref: "lease:stream:run-123",
      authority_packet_ref: "authority-packet:790",
      permission_decision_ref: "decision:allow-790",
      idempotency_key: "idem:lease-revocation:run-123",
      trace_id: "trace:phase4:m10:077",
      correlation_id: "corr:phase4:m10:077",
      release_manifest_ref: "phase4-v6-milestone10",
      lease_ref: "lease:stream:run-123",
      revocation_ref: "lease-revocation:stream:run-123:1",
      revoked_at: "2026-04-19T00:00:00Z",
      lease_scope: %{"tenant_ref" => "tenant:acme", "family" => "runtime_stream"},
      cache_invalidation_ref: "lease-cache-invalidation:stream:run-123:1",
      post_revocation_attempt_ref: "attempt:stream:run-123:after-revoke",
      lease_status: :revoked
    }
  end
end
