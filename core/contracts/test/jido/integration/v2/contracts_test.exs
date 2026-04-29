defmodule Jido.Integration.V2.ContractsTest do
  use ExUnit.Case

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.AttachGrant
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.BoundarySession
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.ExecutionRoute
  alias Jido.Integration.V2.Receipt
  alias Jido.Integration.V2.RecoveryTask
  alias Jido.Integration.V2.ReviewBundle
  alias Jido.Integration.V2.ReviewProjection
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.SubjectRef
  alias Jido.Integration.V2.TargetDescriptor

  test "run and attempt identities stay canonical as contracts broaden" do
    credential_ref =
      CredentialRef.new!(%{
        id: "cred-ref-1",
        connection_id: "conn-1",
        profile_id: "manual_token",
        subject: "operator",
        current_credential_id: "cred-ref-1:v2",
        scopes: ["issues:write"],
        lease_fields: ["access_token"]
      })

    credential =
      Credential.new!(%{
        id: "cred-ref-1:v2",
        credential_ref_id: credential_ref.id,
        connection_id: "conn-1",
        profile_id: "manual_token",
        subject: "operator",
        auth_type: :api_token,
        version: 2,
        scopes: ["issues:write"],
        secret: %{access_token: "gho_test", refresh_token: "ghr_test"},
        lease_fields: ["access_token"],
        source: :refresh,
        source_ref: %{flow: :refresh},
        supersedes_credential_id: "cred-ref-1",
        metadata: %{tenant: "tenant-1"}
      })

    checksum = "sha256:" <> String.duplicate("a", 64)

    artifact_ref =
      ArtifactRef.new!(%{
        artifact_id: "artifact-1",
        run_id: "run-123",
        attempt_id: "run-123:1",
        artifact_type: :tool_output,
        transport_mode: :object_store,
        checksum: checksum,
        size_bytes: 32,
        payload_ref: %{
          store: "s3",
          key: "sha256:" <> String.duplicate("b", 64),
          ttl_s: 86_400,
          access_control: :run_scoped,
          checksum: checksum,
          size_bytes: 32
        },
        retention_class: "tool_outputs",
        redaction_status: :clear
      })

    target_descriptor =
      TargetDescriptor.new!(%{
        target_id: "target-local",
        capability_id: "python3",
        runtime_class: :direct,
        version: "1.0.0",
        features: %{
          feature_ids: ["filesystem", "python3"],
          runspec_versions: ["1.0.0"],
          event_schema_versions: ["1.0.0"]
        },
        constraints: %{sandbox_levels: [:standard]},
        health: :healthy,
        location: %{mode: :local, workspace_root: "/tmp/jido"}
      })

    capability =
      Capability.new!(%{
        id: "github.issue.create",
        connector: "github",
        runtime_class: :direct,
        kind: :operation,
        transport_profile: :action,
        handler: __MODULE__
      })

    run =
      Run.new!(%{
        capability_id: capability.id,
        runtime_class: capability.runtime_class,
        input: %{title: "hello"},
        credential_ref: credential_ref,
        target_id: target_descriptor.target_id,
        artifact_refs: [artifact_ref]
      })

    lease =
      CredentialLease.new!(%{
        lease_id: "lease-1",
        tenant_id: "tenant-contracts",
        credential_ref_id: credential_ref.id,
        credential_id: credential.id,
        connection_id: credential.connection_id,
        profile_id: credential.profile_id,
        subject: credential_ref.subject,
        scopes: ["issues:write"],
        payload: %{access_token: "gho_test"},
        lease_fields: ["access_token"],
        issued_at: ~U[2026-03-09 12:00:00Z],
        expires_at: ~U[2026-03-09 12:05:00Z]
      })

    attempt =
      Attempt.new!(%{
        run_id: run.run_id,
        attempt: 1,
        runtime_class: :direct,
        credential_lease_id: lease.lease_id,
        target_id: target_descriptor.target_id
      })

    assert capability.runtime_class == :direct
    assert run.capability_id == capability.id
    assert run.target_id == target_descriptor.target_id
    assert run.artifact_refs == [artifact_ref]
    assert credential.version == 2
    assert credential.credential_ref_id == credential_ref.id
    assert credential.supersedes_credential_id == "cred-ref-1"
    assert lease.credential_id == credential.id
    assert lease.connection_id == credential.connection_id
    assert lease.profile_id == credential.profile_id
    assert attempt.run_id == run.run_id
    assert attempt.attempt == 1
    assert attempt.attempt_id == "#{run.run_id}:1"
    assert attempt.credential_lease_id == lease.lease_id
    assert attempt.target_id == target_descriptor.target_id
  end

  test "event envelope follows the canonical control-plane shape" do
    payload_ref = %{
      store: "s3",
      key: "sha256:" <> String.duplicate("c", 64),
      ttl_s: 3_600,
      access_control: :run_scoped,
      checksum: "sha256:" <> String.duplicate("d", 64),
      size_bytes: 12
    }

    event =
      Event.new!(%{
        run_id: "run-123",
        attempt: 2,
        seq: 0,
        type: "attempt.started",
        stream: :system,
        level: :info,
        payload: %{capability_id: "github.issue.create"},
        payload_ref: payload_ref,
        target_id: "target-local",
        session_id: "session-1",
        trace: %{
          trace_id: "trace-1",
          span_id: "span-1",
          correlation_id: "corr-1",
          causation_id: "cause-1"
        }
      })

    assert event.schema_version == "1.0"
    assert event.attempt == 2
    assert event.attempt_id == "run-123:2"
    assert event.seq == 0
    assert event.payload_ref == payload_ref
    assert event.target_id == "target-local"
    assert event.session_id == "session-1"
    assert %DateTime{} = event.ts
  end

  test "ordered object helpers require explicit field ordering for stable Zoi schemas" do
    schema =
      Contracts.strict_object!(
        repo: Zoi.string(),
        issue_number: Zoi.integer(),
        body: Zoi.string() |> Zoi.optional()
      )

    assert Enum.map(schema.fields, &elem(&1, 0)) == [:repo, :issue_number, :body]

    assert_raise ArgumentError,
                 ~r/ordered object schema fields must be a keyword list/,
                 fn ->
                   Contracts.strict_object!(%{
                     repo: Zoi.string(),
                     issue_number: Zoi.integer()
                   })
                 end
  end

  test "atomish string normalization uses the bounded contract vocabulary" do
    assert Contracts.normalize_atomish!("llama_cpp_sdk", "provider_identity") ==
             :llama_cpp_sdk

    assert_raise ArgumentError,
                 ~r/provider_identity must be a known atom string/,
                 fn ->
                   Contracts.normalize_atomish!(
                     "unregistered_runtime_atom",
                     "provider_identity"
                   )
                 end
  end

  test "the execution-plane contract packet and boundary metadata vocabulary stay explicit" do
    assert Contracts.execution_plane_contract_packet() == [
             "AuthorityDecision.v1",
             "BoundarySessionDescriptor.v1",
             "ExecutionIntentEnvelope.v1",
             "ExecutionRoute.v1",
             "AttachGrant.v1",
             "CredentialHandleRef.v1",
             "ExecutionEvent.v1",
             "ExecutionOutcome.v1"
           ]

    assert Contracts.boundary_metadata_contract_keys() == [
             "descriptor",
             "route",
             "attach_grant",
             "replay",
             "approval",
             "callback",
             "identity"
           ]

    assert Contracts.lower_restart_authority_contracts() == [
             "BoundarySession.v1",
             "ExecutionRoute.v1",
             "AttachGrant.v1",
             "Receipt.v1",
             "RecoveryTask.v1"
           ]

    assert Contracts.operator_read_contracts() == [
             "ReviewProjection.v1",
             "ReviewBundle.v1"
           ]
  end

  test "lower restart-authority structs normalize stable ids and operator read bundles" do
    run =
      Run.new!(%{
        capability_id: "github.issue.create",
        runtime_class: :direct,
        input: %{},
        credential_ref:
          CredentialRef.new!(%{
            id: "cred-ref-1",
            connection_id: "conn-1",
            profile_id: "manual_token",
            subject: "operator",
            current_credential_id: "cred-ref-1:v2",
            scopes: ["issues:write"],
            lease_fields: ["access_token"]
          })
      })

    attempt =
      Attempt.new!(%{
        run_id: run.run_id,
        attempt: 1,
        runtime_class: :direct
      })

    boundary_session =
      BoundarySession.new!(%{
        session_id: "semantic-1",
        tenant_id: "tenant-1",
        target_id: "target-1",
        status: :attached
      })

    route =
      ExecutionRoute.new!(%{
        run_id: run.run_id,
        attempt_id: attempt.attempt_id,
        boundary_session_id: boundary_session.boundary_session_id,
        target_id: "target-1",
        route_kind: :process,
        status: :accepted_downstream,
        handoff_ref: "handoff-1"
      })

    attach_grant =
      AttachGrant.new!(%{
        boundary_session_id: boundary_session.boundary_session_id,
        route_id: route.route_id,
        subject_id: "operator-1",
        status: :issued
      })

    receipt =
      Receipt.new!(%{
        run_id: run.run_id,
        attempt_id: attempt.attempt_id,
        route_id: route.route_id,
        receipt_kind: :handoff,
        status: :ambiguous
      })

    recovery_task =
      RecoveryTask.new!(%{
        subject_ref: "route:#{route.route_id}",
        run_id: run.run_id,
        attempt_id: attempt.attempt_id,
        route_id: route.route_id,
        receipt_id: receipt.receipt_id,
        reason: "ambiguous_ack",
        status: :pending
      })

    review_projection =
      ReviewProjection.new!(%{
        schema_version: "review_projection.v1",
        projection: "citadel.runtime_observation",
        packet_ref: Contracts.review_packet_ref(run.run_id, attempt.attempt_id),
        subject: SubjectRef.new!(%{kind: :run, id: run.run_id}),
        selected_attempt: SubjectRef.new!(%{kind: :attempt, id: attempt.attempt_id})
      })

    review_bundle =
      ReviewBundle.new!(%{
        review_projection: review_projection,
        run: run,
        attempt: attempt,
        receipts: [receipt],
        recovery_tasks: [recovery_task],
        metadata: %{"boundary_session_id" => boundary_session.boundary_session_id}
      })

    assert String.starts_with?(boundary_session.boundary_session_id, "boundary_session-")
    assert String.starts_with?(route.route_id, "route-")
    assert String.starts_with?(attach_grant.attach_grant_id, "attach_grant-")
    assert receipt.receipt_id == Contracts.receipt_id(run.run_id, attempt.attempt_id, "handoff")
    assert recovery_task.task_id == "route:#{route.route_id}:ambiguous_ack"
    assert review_bundle.review_projection.packet_ref =~ run.run_id
    assert review_bundle.receipts == [receipt]
    assert review_bundle.recovery_tasks == [recovery_task]
  end

  test "ambiguous acknowledgement contracts keep replay and reconciliation explicit" do
    receipt =
      Receipt.new!(%{
        run_id: "run-ack-1",
        attempt_id: "run-ack-1:2",
        route_id: "route-ack-1",
        receipt_kind: :handoff,
        status: :ambiguous,
        metadata: %{"replay_posture" => "hold_until_reconciled"}
      })

    recovery_task =
      RecoveryTask.new!(%{
        subject_ref: "route:route-ack-1",
        run_id: "run-ack-1",
        attempt_id: "run-ack-1:2",
        route_id: "route-ack-1",
        receipt_id: receipt.receipt_id,
        reason: "ambiguous_ack",
        metadata: %{"next_action" => "query_downstream_truth"}
      })

    assert receipt.receipt_id == "run-ack-1:run-ack-1:2:handoff"
    assert receipt.status == :ambiguous
    assert receipt.metadata["replay_posture"] == "hold_until_reconciled"

    assert recovery_task.task_id == "route:route-ack-1:ambiguous_ack"
    assert recovery_task.status == :pending
    assert recovery_task.receipt_id == receipt.receipt_id
    assert recovery_task.metadata["next_action"] == "query_downstream_truth"
  end
end
