defmodule Jido.Integration.V2.ContractsTest do
  use ExUnit.Case

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.Run
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
  end
end
