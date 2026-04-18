defmodule Jido.Integration.V2.StorePostgres.ControlPlaneStoreTest.ClaimCheckStoreProbe do
  @behaviour Jido.Integration.V2.ControlPlane.ClaimCheckStore

  alias Jido.Integration.V2.StorePostgres.ClaimCheckStore
  alias Jido.Integration.V2.StorePostgres.Repo

  def stage_blob(payload_ref, encoded, metadata) do
    send(self(), {:claim_check_stage_in_transaction?, Repo.in_transaction?()})
    ClaimCheckStore.stage_blob(payload_ref, encoded, metadata)
  end

  def fetch_blob(payload_ref), do: ClaimCheckStore.fetch_blob(payload_ref)

  def register_reference(payload_ref, attrs),
    do: ClaimCheckStore.register_reference(payload_ref, attrs)

  def fetch_blob_metadata(payload_ref), do: ClaimCheckStore.fetch_blob_metadata(payload_ref)
  def count_live_references(payload_ref), do: ClaimCheckStore.count_live_references(payload_ref)
  def sweep_staged_payloads(opts \\ []), do: ClaimCheckStore.sweep_staged_payloads(opts)
  def garbage_collect(opts \\ []), do: ClaimCheckStore.garbage_collect(opts)
  def reset!, do: ClaimCheckStore.reset!()
end

defmodule Jido.Integration.V2.StorePostgres.ControlPlaneStoreTest.SlowClaimCheckStoreProbe do
  @behaviour Jido.Integration.V2.ControlPlane.ClaimCheckStore

  alias Jido.Integration.V2.StorePostgres.ClaimCheckStore
  alias Jido.Integration.V2.StorePostgres.Repo

  @probe_app :jido_integration_v2_store_postgres
  @pid_key :claim_check_probe_pid
  @delay_key :claim_check_probe_delay_ms

  def stage_blob(payload_ref, encoded, metadata) do
    send_probe_message({:claim_check_stage_in_transaction?, Repo.in_transaction?()})
    send_probe_message({:claim_check_stage_delay_started, System.monotonic_time(:millisecond)})
    Process.sleep(probe_delay_ms())
    ClaimCheckStore.stage_blob(payload_ref, encoded, metadata)
  end

  def fetch_blob(payload_ref), do: ClaimCheckStore.fetch_blob(payload_ref)

  def register_reference(payload_ref, attrs),
    do: ClaimCheckStore.register_reference(payload_ref, attrs)

  def fetch_blob_metadata(payload_ref), do: ClaimCheckStore.fetch_blob_metadata(payload_ref)
  def count_live_references(payload_ref), do: ClaimCheckStore.count_live_references(payload_ref)
  def sweep_staged_payloads(opts \\ []), do: ClaimCheckStore.sweep_staged_payloads(opts)
  def garbage_collect(opts \\ []), do: ClaimCheckStore.garbage_collect(opts)
  def reset!, do: ClaimCheckStore.reset!()

  defp send_probe_message(message) do
    case Application.get_env(@probe_app, @pid_key) do
      pid when is_pid(pid) -> send(pid, message)
      _other -> :ok
    end
  end

  defp probe_delay_ms do
    Application.get_env(@probe_app, @delay_key, 0)
  end
end

defmodule Jido.Integration.V2.StorePostgres.ControlPlaneStoreTest do
  use Jido.Integration.V2.StorePostgres.DataCase

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias Jido.Integration.V2.CompatibilityResult
  alias Jido.Integration.V2.ConsumerManifest
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ControlPlane.ClaimCheck
  alias Jido.Integration.V2.ControlPlane.ClaimCheckTelemetry
  alias Jido.Integration.V2.InferenceExecutionContext
  alias Jido.Integration.V2.InferenceRequest
  alias Jido.Integration.V2.InferenceResult
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.StorePostgres.ArtifactStore
  alias Jido.Integration.V2.StorePostgres.AttemptStore
  alias Jido.Integration.V2.StorePostgres.ClaimCheckStore
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

  test "lists run attempt history in attempt order" do
    run = run_fixture()
    first_attempt = attempt_fixture(run, %{attempt: 1})
    second_attempt = attempt_fixture(run, %{attempt: 2, aggregator_epoch: 2})

    assert :ok = RunStore.put_run(run)
    assert :ok = AttemptStore.put_attempt(first_attempt)
    assert :ok = AttemptStore.put_attempt(second_attempt)

    assert Enum.map(AttemptStore.list_attempts(run.run_id), & &1.attempt) == [1, 2]
  end

  test "preserves JSON-safe string keys for durable runtime payload families" do
    run =
      run_fixture(%{
        input: %{prompt: "hello", metadata: %{tenant_id: "tenant-1"}},
        result: %{
          inference_result: %{status: :ok},
          compatibility_result: %{metadata: %{route: :cloud}}
        }
      })

    attempt =
      attempt_fixture(run, %{
        output: %{
          inference_result: %{status: :ok},
          compatibility_result: %{metadata: %{route: :cloud}}
        }
      })

    event =
      event_fixture(run, attempt, %{
        payload: %{authorization: "Bearer 123", route: :cloud},
        trace: %{trace_id: "trace-1"}
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
    assert {:ok, stored_attempt} = AttemptStore.fetch_attempt(attempt.attempt_id)
    [stored_event] = EventStore.list_events(run.run_id)

    assert stored_run.input["prompt"] == "hello"
    assert stored_run.input["metadata"]["tenant_id"] == "tenant-1"
    assert stored_run.result["compatibility_result"]["metadata"]["route"] == "cloud"
    assert stored_attempt.output["compatibility_result"]["metadata"]["route"] == "cloud"
    assert stored_event.payload["route"] == "cloud"
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

  test "claim-checks oversized inference payloads before durable writes and tracks live references" do
    attach_claim_check_telemetry([:stage, :blob_gc_skipped_live_reference])

    Application.put_env(
      :jido_integration_v2_control_plane,
      :claim_check_store,
      Jido.Integration.V2.StorePostgres.ControlPlaneStoreTest.ClaimCheckStoreProbe
    )

    large_text = large_text()
    spec = oversized_failed_inference_spec(large_text)

    assert {:ok, recorded} = ControlPlane.record_inference_attempt(spec)
    assert_stage_uploads_outside_transaction(4)

    assert {:ok, stored_run} = RunStore.fetch_run(recorded.run.run_id)
    assert {:ok, stored_attempt} = AttemptStore.fetch_attempt(recorded.attempt.attempt_id)
    events = EventStore.list_events(recorded.run.run_id)
    terminal_event = List.last(events)

    assert ClaimCheck.claim_checked?(stored_run.input)
    assert ClaimCheck.claim_checked?(stored_run.result)
    assert ClaimCheck.claim_checked?(stored_attempt.output)
    assert ClaimCheck.claim_checked?(terminal_event.payload)

    assert {:ok, input_metadata} =
             ClaimCheckStore.fetch_blob_metadata(stored_run.input_payload_ref)

    assert {:ok, result_metadata} =
             ClaimCheckStore.fetch_blob_metadata(stored_run.result_payload_ref)

    assert {:ok, output_metadata} =
             ClaimCheckStore.fetch_blob_metadata(stored_attempt.output_payload_ref)

    assert {:ok, event_metadata} = ClaimCheckStore.fetch_blob_metadata(terminal_event.payload_ref)

    assert input_metadata.status == :referenced
    assert result_metadata.status == :referenced
    assert output_metadata.status == :referenced
    assert event_metadata.status == :referenced
    assert input_metadata.trace_id == "trace-claim-check-1"
    assert event_metadata.trace_id == "trace-claim-check-1"

    assert ClaimCheckStore.count_live_references(stored_run.input_payload_ref) == 1
    assert ClaimCheckStore.count_live_references(stored_run.result_payload_ref) == 1
    assert ClaimCheckStore.count_live_references(stored_attempt.output_payload_ref) == 1
    assert ClaimCheckStore.count_live_references(terminal_event.payload_ref) == 1

    assert {:ok, resolved_input} =
             ClaimCheck.resolve_json(stored_run.input, stored_run.input_payload_ref)

    assert {:ok, resolved_terminal_payload} =
             ClaimCheck.resolve_json(terminal_event.payload, terminal_event.payload_ref)

    assert get_in(resolved_input, ["request", "messages", Access.at(0), "content"]) == large_text
    assert get_in(resolved_terminal_payload, ["error", "message"]) == large_text

    assert {:ok, gc_result} = ClaimCheckStore.garbage_collect(older_than_s: 0)
    assert gc_result.deleted_count == 0
    assert gc_result.skipped_live_reference_count >= 4

    assert_claim_check_events(:stage, 4, fn measurements, metadata ->
      assert measurements.count == 1
      assert measurements.payload_bytes > 64 * 1024
      assert is_integer(measurements.latency_ms)
      assert measurements.latency_ms >= 0
      assert metadata.trace_id == "trace-claim-check-1"
      assert metadata.source_component == :claim_check
      assert metadata.store_backend == "claim_check_hot"
      assert String.starts_with?(metadata.payload_ref.key, "sha256/")
    end)

    assert_claim_check_events(:blob_gc_skipped_live_reference, 4, fn measurements, metadata ->
      assert measurements.count == 1
      assert measurements.payload_bytes > 64 * 1024
      assert metadata.trace_id == "trace-claim-check-1"
      assert metadata.source_component == :store_postgres
      assert metadata.store_backend == :store_postgres
      assert metadata.live_reference_count == 1
      assert String.starts_with?(metadata.payload_ref.key, "sha256/")
    end)
  end

  test "uses content-addressed claim-check keys and sweeps staged unreferenced payloads" do
    attach_claim_check_telemetry([:orphaned_staged_payload])

    large_payload = %{
      "contract_version" => "test",
      "messages" => [%{"role" => "user", "content" => large_text()}]
    }

    assert {:ok, first} =
             ClaimCheck.prepare_json(large_payload,
               payload_kind: :test_payload,
               trace_id: "trace-claim-check-orphan",
               redaction_class: "test_payload"
             )

    assert {:ok, second} =
             ClaimCheck.prepare_json(large_payload,
               payload_kind: :test_payload,
               trace_id: "trace-claim-check-orphan",
               redaction_class: "test_payload"
             )

    assert first.payload_ref == second.payload_ref
    assert ClaimCheckStore.count_live_references(first.payload_ref) == 0

    assert {:ok, staged_metadata} = ClaimCheckStore.fetch_blob_metadata(first.payload_ref)
    assert staged_metadata.status == :staged
    assert staged_metadata.payload_kind == "test_payload"
    assert String.starts_with?(first.payload_ref.key, "sha256/")

    assert {:ok, sweep_result} = ClaimCheckStore.sweep_staged_payloads(older_than_s: 0)
    assert sweep_result.deleted_count == 1

    assert {:ok, swept_metadata} = ClaimCheckStore.fetch_blob_metadata(first.payload_ref)
    assert swept_metadata.status == :swept
    assert ClaimCheckStore.fetch_blob(first.payload_ref) == :error

    assert_claim_check_events(:orphaned_staged_payload, 1, fn measurements, metadata ->
      assert measurements.count == 1
      assert measurements.payload_bytes > 64 * 1024
      assert metadata.trace_id == "trace-claim-check-orphan"
      assert metadata.source_component == :store_postgres
      assert metadata.store_backend == :store_postgres
      assert metadata.payload_kind == "test_payload"
      assert metadata.payload_ref.store == first.payload_ref.store
      assert metadata.payload_ref.key == first.payload_ref.key
      assert metadata.payload_ref.checksum == first.payload_ref.checksum
      assert metadata.payload_ref.size_bytes == first.payload_ref.size_bytes
    end)
  end

  test "slow claim-check staging leaves unrelated Postgres work available while uploads are delayed" do
    attach_claim_check_telemetry([:stage])

    Application.put_env(
      :jido_integration_v2_control_plane,
      :claim_check_store,
      Jido.Integration.V2.StorePostgres.ControlPlaneStoreTest.SlowClaimCheckStoreProbe
    )

    Application.put_env(:jido_integration_v2_store_postgres, :claim_check_probe_pid, self())
    Application.put_env(:jido_integration_v2_store_postgres, :claim_check_probe_delay_ms, 200)

    on_exit(fn ->
      Application.delete_env(:jido_integration_v2_store_postgres, :claim_check_probe_pid)
      Application.delete_env(:jido_integration_v2_store_postgres, :claim_check_probe_delay_ms)
    end)

    spec = oversized_failed_inference_spec(large_text())

    task =
      Task.async(fn ->
        receive do
          :run_slow_claim_check_recording -> ControlPlane.record_inference_attempt(spec)
        end
      end)

    Sandbox.allow(Repo, self(), task.pid)
    send(task.pid, :run_slow_claim_check_recording)

    assert_receive {:claim_check_stage_in_transaction?, false}, 1_000
    assert_receive {:claim_check_stage_delay_started, _started_at_ms}, 1_000

    {query_time_us, query_result} =
      :timer.tc(fn ->
        SQL.query!(Repo, "SELECT 1", [])
      end)

    assert query_result.rows == [[1]]
    assert query_time_us < 150_000
    assert {:ok, recorded} = Task.await(task, 5_000)
    assert recorded.run.run_id == "run-claim-check-1"
    assert_stage_uploads_outside_transaction(3)

    assert_claim_check_events(:stage, 4, fn measurements, metadata ->
      assert measurements.count == 1
      assert measurements.payload_bytes > 64 * 1024
      assert measurements.latency_ms >= 200
      assert metadata.trace_id == "trace-claim-check-1"
      assert metadata.store_backend == "claim_check_hot"
    end)
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

  defp oversized_failed_inference_spec(large_text) do
    %{
      request:
        InferenceRequest.new!(%{
          request_id: "req-claim-check-1",
          operation: :generate_text,
          messages: [%{role: "user", content: large_text}],
          prompt: nil,
          model_preference: %{provider: "openai", id: "gpt-4o-mini"},
          target_preference: %{target_class: "cloud_provider"},
          stream?: false,
          tool_policy: %{},
          output_constraints: %{format: "text"},
          metadata: %{tenant_id: "tenant-1"}
        }),
      context:
        InferenceExecutionContext.new!(%{
          run_id: "run-claim-check-1",
          attempt_id: "run-claim-check-1:1",
          authority_source: :jido_integration,
          decision_ref: "decision-claim-check-1",
          authority_ref: nil,
          boundary_ref: nil,
          credential_scope: %{scopes: ["model:invoke"]},
          network_policy: %{egress: "restricted"},
          observability: %{trace_id: "trace-claim-check-1"},
          streaming_policy: %{checkpoint_policy: :disabled},
          replay: %{replayable?: false, recovery_class: nil},
          metadata: %{phase: "phase_2"}
        }),
      consumer_manifest:
        ConsumerManifest.new!(%{
          consumer: "jido_integration_req_llm",
          accepted_runtime_kinds: [:client],
          accepted_management_modes: [:provider_managed],
          accepted_protocols: [:openai_chat_completions],
          required_capabilities: %{},
          optional_capabilities: %{tool_calling?: false},
          constraints: %{checkpoint_policy: :disabled},
          metadata: %{phase: "phase_2"}
        }),
      compatibility_result:
        CompatibilityResult.new!(%{
          compatible?: true,
          reason: :protocol_match,
          resolved_runtime_kind: :client,
          resolved_management_mode: :provider_managed,
          resolved_protocol: nil,
          warnings: [],
          missing_requirements: [],
          metadata: %{route: "cloud"}
        }),
      result:
        InferenceResult.new!(%{
          run_id: "run-claim-check-1",
          attempt_id: "run-claim-check-1:1",
          status: :error,
          streaming?: false,
          endpoint_id: nil,
          stream_id: nil,
          finish_reason: :error,
          usage: nil,
          error: %{message: large_text, reason: :timeout},
          metadata: %{provider: "openai"}
        })
    }
  end

  defp assert_stage_uploads_outside_transaction(expected_count) do
    Enum.each(1..expected_count, fn _index ->
      assert_receive {:claim_check_stage_in_transaction?, false}
    end)
  end

  defp attach_claim_check_telemetry(event_keys) do
    handler_id = "claim-check-telemetry-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      Enum.map(event_keys, &ClaimCheckTelemetry.event/1),
      &__MODULE__.handle_claim_check_telemetry/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  def handle_claim_check_telemetry(event, measurements, metadata, pid) do
    send(pid, {:claim_check_telemetry, event, measurements, metadata})
  end

  defp assert_claim_check_events(event_key, expected_count, assertion_fun) do
    event = ClaimCheckTelemetry.event(event_key)

    Enum.each(1..expected_count, fn _index ->
      assert_receive {:claim_check_telemetry, ^event, measurements, metadata}, 1_000
      assertion_fun.(measurements, metadata)
    end)
  end

  defp large_text do
    String.duplicate("oversized-claim-check-payload-", 3_000)
  end
end
