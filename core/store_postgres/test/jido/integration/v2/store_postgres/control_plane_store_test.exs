defmodule Jido.Integration.V2.StorePostgres.ControlPlaneStoreTest do
  use Jido.Integration.V2.StorePostgres.DataCase

  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.StorePostgres.ArtifactStore
  alias Jido.Integration.V2.StorePostgres.AttemptStore
  alias Jido.Integration.V2.StorePostgres.EventStore
  alias Jido.Integration.V2.StorePostgres.RunStore
  alias Jido.Integration.V2.StorePostgres.TargetStore
  alias Jido.Integration.V2.TargetDescriptor

  test "round-trips runs attempts and ordered events" do
    run = run_fixture()
    attempt = attempt_fixture(run)

    assert :ok = RunStore.put_run(run)
    assert :ok = AttemptStore.put_attempt(attempt)

    first = event_fixture(run, attempt, %{seq: 0, type: "run.started"})
    second = event_fixture(run, attempt, %{seq: 1, type: "attempt.completed"})

    assert :ok =
             EventStore.append_events(
               [first, second],
               aggregator_id: attempt.aggregator_id,
               aggregator_epoch: attempt.aggregator_epoch
             )

    assert {:ok, persisted_run} = RunStore.fetch_run(run.run_id)
    assert {:ok, persisted_attempt} = AttemptStore.fetch_attempt(attempt.attempt_id)
    assert persisted_run.run_id == run.run_id
    assert persisted_attempt.attempt_id == attempt.attempt_id

    assert [listed_first, listed_second] = EventStore.list_events(run.run_id)
    assert listed_first.seq == 0
    assert listed_second.seq == 1
    assert EventStore.next_seq(run.run_id, attempt.attempt_id) == 2
  end

  test "enforces idempotency and epoch fencing on event append" do
    run = run_fixture()
    attempt = attempt_fixture(run, %{aggregator_id: "agg-9", aggregator_epoch: 2})
    event = event_fixture(run, attempt, %{seq: 0, type: "attempt.started"})
    conflict = %{event | payload: %{"changed" => true}}

    assert :ok = RunStore.put_run(run)
    assert :ok = AttemptStore.put_attempt(attempt)

    assert :ok =
             EventStore.append_events(
               [event],
               aggregator_id: attempt.aggregator_id,
               aggregator_epoch: attempt.aggregator_epoch
             )

    assert :ok =
             EventStore.append_events(
               [event],
               aggregator_id: attempt.aggregator_id,
               aggregator_epoch: attempt.aggregator_epoch
             )

    assert {:error, :event_conflict} =
             EventStore.append_events(
               [conflict],
               aggregator_id: attempt.aggregator_id,
               aggregator_epoch: attempt.aggregator_epoch
             )

    assert {:error, :stale_aggregator_epoch} =
             EventStore.append_events(
               [event_fixture(run, attempt, %{seq: 1, type: "attempt.completed"})],
               aggregator_id: attempt.aggregator_id,
               aggregator_epoch: 1
             )

    assert length(EventStore.list_events(run.run_id)) == 1
  end

  test "parameterizes identifiers and redacts secrets in durable run and event truth" do
    run =
      run_fixture(%{
        run_id: "run'; DROP TABLE runs; --",
        input: %{access_token: "top-secret", nested: %{api_key: "still-secret"}}
      })

    attempt = attempt_fixture(run)

    event =
      event_fixture(run, attempt, %{
        payload: %{authorization: "Bearer 123", safe: "value"},
        seq: 0
      })

    assert :ok = RunStore.put_run(run)
    assert :ok = AttemptStore.put_attempt(attempt)

    assert :ok =
             EventStore.append_events(
               [event],
               aggregator_id: attempt.aggregator_id,
               aggregator_epoch: attempt.aggregator_epoch
             )

    assert {:ok, stored_run} = RunStore.fetch_run(run.run_id)
    assert fetch_map_value(stored_run.input, :access_token) == Redaction.redacted()

    assert fetch_map_value(fetch_map_value(stored_run.input, :nested), :api_key) ==
             Redaction.redacted()

    [stored_event] = EventStore.list_events(run.run_id)
    assert fetch_map_value(stored_event.payload, :authorization) == Redaction.redacted()
    assert fetch_map_value(stored_event.payload, :safe) == "value"
  end

  test "round-trips artifact refs with explicit integrity metadata" do
    run = run_fixture()
    attempt = attempt_fixture(run)
    artifact_ref = artifact_ref_fixture(run, attempt)

    assert :ok = RunStore.put_run(run)
    assert :ok = AttemptStore.put_attempt(attempt)
    assert :ok = ArtifactStore.put_artifact_ref(artifact_ref)
    assert {:ok, persisted_artifact} = ArtifactStore.fetch_artifact_ref(artifact_ref.artifact_id)
    assert [listed_artifact] = ArtifactStore.list_artifact_refs(run.run_id)

    assert persisted_artifact == artifact_ref
    assert listed_artifact == artifact_ref
  end

  test "persists target descriptors and preserves compatibility inputs" do
    compatible_target = target_descriptor_fixture(%{target_id: "target-compatible"})

    incompatible_target =
      target_descriptor_fixture(%{
        target_id: "target-incompatible",
        version: "1.0.0",
        features: %{
          feature_ids: ["python3"],
          runspec_versions: ["0.9.0"],
          event_schema_versions: ["0.9.0"]
        }
      })

    assert :ok = TargetStore.put_target_descriptor(compatible_target)
    assert :ok = TargetStore.put_target_descriptor(incompatible_target)
    assert {:ok, persisted_target} = TargetStore.fetch_target_descriptor("target-compatible")

    assert [%TargetDescriptor{}, %TargetDescriptor{}] =
             Enum.sort_by(TargetStore.list_target_descriptors(), & &1.target_id)

    assert persisted_target == compatible_target

    assert {:ok, %{runspec_version: "1.1.0", event_schema_version: "1.2.0"}} =
             TargetDescriptor.compatibility(persisted_target, %{
               capability_id: "python3",
               runtime_class: :direct,
               version_requirement: "~> 2.0",
               required_features: ["docker"],
               accepted_runspec_versions: ["1.0.0", "1.1.0"],
               accepted_event_schema_versions: ["1.0.0", "1.2.0"]
             })
  end
end
