defmodule Jido.Integration.V2.ZoiStandardTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.Gateway
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.InvocationRequest
  alias Jido.Integration.V2.PolicyDecision
  alias Jido.Integration.V2.ReviewProjection
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.RuntimeResult
  alias Jido.Integration.V2.SubjectRef
  alias Jido.Integration.V2.TargetDescriptor
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  @canonical_zoi_modules [
    ArtifactRef,
    Attempt,
    Credential,
    CredentialLease,
    CredentialRef,
    Event,
    EvidenceRef,
    Gateway,
    Gateway.Policy,
    GovernanceRef,
    InvocationRequest,
    PolicyDecision,
    ReviewProjection,
    Run,
    RuntimeResult,
    SubjectRef,
    TargetDescriptor,
    TriggerCheckpoint,
    TriggerRecord
  ]

  test "shared core contract models expose the canonical zoi surface" do
    for module <- @canonical_zoi_modules do
      assert Code.ensure_loaded?(module),
             "#{inspect(module)} must load before its canonical Zoi exports are checked"

      assert function_exported?(module, :schema, 0),
             "#{inspect(module)} must expose schema/0"

      assert function_exported?(module, :new, 1),
             "#{inspect(module)} must expose new/1"

      assert function_exported?(module, :new!, 1),
             "#{inspect(module)} must expose new!/1"

      assert {:ok, struct} = module.new(valid_attrs(module))
      assert match?(%{__struct__: ^module}, struct)
      assert match?(%{__struct__: ^module}, module.new!(valid_attrs(module)))
    end
  end

  test "core contract struct files do not drift back to manual defstruct definitions" do
    contract_root =
      __DIR__
      |> Path.join("../../../lib/jido/integration/v2")
      |> Path.expand()

    offenders =
      contract_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(fn file ->
        content = File.read!(file)

        String.contains?(content, "defstruct") and
          not String.contains?(content, "@schema Zoi.struct(")
      end)
      |> Enum.map(&Path.relative_to(&1, contract_root))

    assert offenders == []
  end

  defp valid_attrs(ArtifactRef) do
    %{
      artifact_id: "artifact-1",
      run_id: "run-1",
      attempt_id: "run-1:1",
      artifact_type: :tool_output,
      transport_mode: :object_store,
      checksum: "sha256:" <> String.duplicate("a", 64),
      size_bytes: 42,
      payload_ref: %{
        store: "s3",
        key: "runs/run-1/artifacts/1",
        ttl_s: 300,
        access_control: :run_scoped,
        checksum: "sha256:" <> String.duplicate("a", 64),
        size_bytes: 42
      },
      retention_class: "ephemeral",
      redaction_status: :clear
    }
  end

  defp valid_attrs(Attempt) do
    %{
      run_id: "run-1",
      attempt: 1,
      runtime_class: :direct
    }
  end

  defp valid_attrs(Credential) do
    %{
      id: "cred-1",
      connection_id: "conn-1",
      subject: "operator",
      auth_type: :oauth2,
      scopes: ["issues:read"],
      secret: %{access_token: "token", refresh_token: "refresh"},
      metadata: %{tenant: "tenant-1"}
    }
  end

  defp valid_attrs(CredentialLease) do
    %{
      lease_id: "lease-1",
      credential_ref_id: "cred-ref-1",
      subject: "operator",
      scopes: ["issues:read"],
      payload: %{access_token: "token"},
      issued_at: ~U[2026-03-19 00:00:00Z],
      expires_at: ~U[2026-03-19 00:05:00Z]
    }
  end

  defp valid_attrs(CredentialRef) do
    %{
      id: "cred-ref-1",
      subject: "operator",
      scopes: ["issues:read"],
      metadata: %{tenant: "tenant-1"}
    }
  end

  defp valid_attrs(Event) do
    %{
      event_id: "event-1",
      run_id: "run-1",
      attempt: 1,
      attempt_id: "run-1:1",
      seq: 1,
      type: "attempt.started",
      stream: :system,
      level: :info,
      payload: %{status: "running"},
      trace: %{trace_id: "trace-1"},
      ts: ~U[2026-03-19 00:00:00Z]
    }
  end

  defp valid_attrs(EvidenceRef) do
    %{
      kind: :event,
      id: "event-1",
      packet_ref: "jido://v2/review_packet/run/run-1?attempt_id=run-1%3A1",
      subject: SubjectRef.new!(valid_attrs(SubjectRef)),
      metadata: %{type: "attempt.started"}
    }
  end

  defp valid_attrs(Gateway) do
    %{
      actor_id: "actor-1",
      tenant_id: "tenant-1",
      environment: :prod,
      trace_id: "trace-1",
      credential_ref: CredentialRef.new!(valid_attrs(CredentialRef)),
      runtime_class: :direct,
      allowed_operations: ["github.issue.fetch"],
      sandbox: %{level: :standard, egress: :restricted, approvals: :auto, allowed_tools: []},
      metadata: %{request_id: "req-1"}
    }
  end

  defp valid_attrs(GovernanceRef) do
    %{
      kind: :policy_decision,
      id: "event-1",
      subject: SubjectRef.new!(valid_attrs(SubjectRef)),
      evidence: [EvidenceRef.new!(valid_attrs(EvidenceRef))],
      metadata: %{status: :denied}
    }
  end

  defp valid_attrs(Gateway.Policy) do
    %{
      actor: %{required: true, allowed_ids: ["actor-1"]},
      tenant: %{required: true, allowed_ids: ["tenant-1"]},
      environment: %{allowed: ["prod"]},
      capability: %{allowed_operations: ["github.issue.fetch"], required_scopes: ["issues:read"]},
      runtime: %{allowed: [:direct]},
      sandbox: %{
        level: :standard,
        egress: :restricted,
        approvals: :auto,
        file_scope: nil,
        allowed_tools: []
      }
    }
  end

  defp valid_attrs(InvocationRequest) do
    %{
      capability_id: "github.issue.fetch",
      connection_id: "conn-1",
      actor_id: "actor-1",
      tenant_id: "tenant-1",
      environment: :prod,
      trace_id: "trace-1",
      input: %{issue_number: 123},
      allowed_operations: ["github.issue.fetch"],
      sandbox: %{level: :standard, egress: :restricted, approvals: :auto, allowed_tools: []},
      target_id: "target-1",
      aggregator_id: "control_plane",
      aggregator_epoch: 1,
      extensions: [request_label: "ticket-fetch"]
    }
  end

  defp valid_attrs(ReviewProjection) do
    %{
      schema_version: "jido.integration.v2",
      projection: "operator.review_packet",
      packet_ref: "jido://v2/review_packet/run/run-1?attempt_id=run-1%3A1",
      subject: SubjectRef.new!(valid_attrs(SubjectRef)),
      selected_attempt:
        SubjectRef.new!(%{
          kind: :attempt,
          id: "run-1:1",
          metadata: %{attempt: 1, run_id: "run-1"}
        }),
      evidence_refs: [EvidenceRef.new!(valid_attrs(EvidenceRef))],
      governance_refs: [GovernanceRef.new!(valid_attrs(GovernanceRef))]
    }
  end

  defp valid_attrs(PolicyDecision) do
    %{
      status: :allowed,
      reasons: [],
      execution_policy: %{runtime_class: :direct},
      audit_context: %{capability_id: "github.issue.fetch"}
    }
  end

  defp valid_attrs(Run) do
    %{
      run_id: "run-1",
      capability_id: "github.issue.fetch",
      runtime_class: :direct,
      status: :accepted,
      input: %{issue_number: 123},
      credential_ref: CredentialRef.new!(valid_attrs(CredentialRef)),
      target_id: "target-1",
      artifact_refs: [ArtifactRef.new!(valid_attrs(ArtifactRef))]
    }
  end

  defp valid_attrs(RuntimeResult) do
    %{
      output: %{issue_id: "123"},
      runtime_ref_id: "runtime-ref-1",
      events: [
        %{
          type: "attempt.completed",
          stream: :system,
          level: :info,
          payload: %{status: "ok"},
          trace: %{trace_id: "trace-1"}
        }
      ],
      artifacts: [ArtifactRef.new!(valid_attrs(ArtifactRef))]
    }
  end

  defp valid_attrs(SubjectRef) do
    %{
      kind: :run,
      id: "run-1",
      metadata: %{tenant_id: "tenant-1"}
    }
  end

  defp valid_attrs(TargetDescriptor) do
    %{
      target_id: "target-1",
      capability_id: "runtime.asm",
      runtime_class: :session,
      version: "1.0.0",
      features: %{
        feature_ids: ["streaming", "resume"],
        runspec_versions: ["1.0.0"],
        event_schema_versions: ["1.0.0"]
      },
      constraints: %{
        regions: ["us-east-1"],
        sandbox_levels: [:standard]
      },
      health: :healthy,
      location: %{mode: :local, workspace_root: "/tmp/jido-target"}
    }
  end

  defp valid_attrs(TriggerCheckpoint) do
    %{
      tenant_id: "tenant-1",
      connector_id: "github",
      trigger_id: "github.issue.updated",
      partition_key: "tenant-1:issues",
      cursor: "cursor-1",
      revision: 1
    }
  end

  defp valid_attrs(TriggerRecord) do
    %{
      admission_id: "trigger-1",
      source: :webhook,
      connector_id: "github",
      trigger_id: "github.issue.updated",
      capability_id: "github.issue.updated",
      tenant_id: "tenant-1",
      dedupe_key: "delivery-1",
      payload: %{delivery_id: "delivery-1"},
      signal: %{type: "github.issue.updated"},
      status: :accepted
    }
  end
end
