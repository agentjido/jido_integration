defmodule Jido.Integration.V2.StorePostgres.Fixtures do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.TargetDescriptor
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  def run_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        run_id: "run-#{System.unique_integer([:positive])}",
        capability_id: "test.echo",
        runtime_class: :direct,
        status: :accepted,
        input: %{prompt: "hello"},
        credential_ref:
          CredentialRef.new!(%{
            id: "cred-#{System.unique_integer([:positive])}",
            subject: "tester",
            scopes: ["echo:write"]
          })
      })

    Run.new!(attrs)
  end

  def attempt_fixture(%Run{} = run, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        run_id: run.run_id,
        attempt: 1,
        runtime_class: run.runtime_class,
        status: :accepted,
        aggregator_id: "agg-1",
        aggregator_epoch: 1
      })

    Attempt.new!(attrs)
  end

  def event_fixture(%Run{} = run, attempt, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        event_id: "event-#{System.unique_integer([:positive])}",
        schema_version: Contracts.schema_version(),
        run_id: run.run_id,
        attempt: attempt && attempt.attempt,
        attempt_id: attempt && attempt.attempt_id,
        seq: 0,
        type: "attempt.started",
        stream: :system,
        level: :info,
        payload: %{},
        trace: %{trace_id: "trace-1", span_id: "span-1"},
        ts: Contracts.now()
      })

    Event.new!(attrs)
  end

  def artifact_ref_fixture(%Run{} = run, attempt, attrs \\ %{}) do
    checksum = "sha256:" <> String.duplicate("a", 64)

    attrs =
      Enum.into(attrs, %{
        artifact_id: "artifact-#{System.unique_integer([:positive])}",
        run_id: run.run_id,
        attempt_id: attempt.attempt_id,
        artifact_type: :tool_output,
        transport_mode: :object_store,
        checksum: checksum,
        size_bytes: 256,
        payload_ref: %{
          store: "s3",
          key: "sha256:" <> String.duplicate("b", 64),
          ttl_s: 86_400,
          access_control: :run_scoped,
          checksum: checksum,
          size_bytes: 256
        },
        retention_class: "tool_outputs",
        redaction_status: :clear,
        metadata: %{source: "fixture"}
      })

    ArtifactRef.new!(attrs)
  end

  def target_descriptor_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        target_id: "target-#{System.unique_integer([:positive])}",
        capability_id: "python3",
        runtime_class: :direct,
        version: "2.1.0",
        features: %{
          feature_ids: ["docker", "python3"],
          runspec_versions: ["1.0.0", "1.1.0"],
          event_schema_versions: ["1.0.0", "1.2.0"]
        },
        constraints: %{regions: ["us-west-2"], sandbox_levels: [:standard]},
        health: :healthy,
        location: %{mode: :beam, region: "us-west-2", workspace_root: "/srv/jido"}
      })

    TargetDescriptor.new!(attrs)
  end

  def trigger_record_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        admission_id: "trigger-#{System.unique_integer([:positive])}",
        source: :webhook,
        connector_id: "github",
        trigger_id: "issues.opened",
        capability_id: "github.issue.ingest",
        tenant_id: "tenant-1",
        external_id: "delivery-#{System.unique_integer([:positive])}",
        dedupe_key: "dedupe-#{System.unique_integer([:positive])}",
        payload: %{"action" => "opened"},
        signal: %{"type" => "github.issue.opened", "source" => "/ingress/webhook"}
      })

    TriggerRecord.new!(attrs)
  end

  def trigger_checkpoint_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        tenant_id: "tenant-1",
        connector_id: "market_data",
        trigger_id: "ticks.pull",
        partition_key: "AAPL",
        cursor: "cursor-#{System.unique_integer([:positive])}",
        last_event_id: "event-#{System.unique_integer([:positive])}",
        last_event_time: Contracts.now()
      })

    TriggerCheckpoint.new!(attrs)
  end

  def credential_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        id: "cred-#{System.unique_integer([:positive])}",
        subject: "operator",
        auth_type: :oauth2,
        scopes: ["repo"],
        secret: %{access_token: "secret-token"},
        metadata: %{owner: "test"}
      })

    Credential.new!(attrs)
  end

  def lease_fixture(%Credential{} = credential, attrs \\ %{}) do
    issued_at = Contracts.now()

    attrs =
      Enum.into(attrs, %{
        lease_id: "lease-#{System.unique_integer([:positive])}",
        credential_ref_id: credential.id,
        subject: credential.subject,
        scopes: credential.scopes,
        payload: credential.secret,
        issued_at: issued_at,
        expires_at: DateTime.add(issued_at, 300, :second),
        metadata: %{credential_id: credential.id}
      })

    CredentialLease.new!(attrs)
  end
end
