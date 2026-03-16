defmodule Jido.Integration.V2.DispatchRuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.TestTmpDir
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.DispatchRuntime
  alias Jido.Integration.V2.DispatchRuntime.Dispatch
  alias Jido.Integration.V2.DispatchRuntime.Telemetry, as: DispatchTelemetry
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.TriggerRecord

  defmodule ScriptedCapability do
    def run(input, context) do
      trigger = fetch(input, :trigger)
      payload = fetch(trigger, :payload)
      test_pid = payload["test_pid"]

      if is_pid(test_pid) do
        send(test_pid, {:capability_attempt, context.run_id, context.attempt})
      end

      sleep_ms = payload["sleep_ms"] || 0

      if sleep_ms > 0 do
        Process.sleep(sleep_ms)
      end

      fail_attempts = payload["fail_attempts"] || 0

      if context.attempt <= fail_attempts do
        {:error, {:scripted_failure, context.attempt}}
      else
        {:ok,
         %{
           attempt: context.attempt,
           run_id: context.run_id,
           value: payload["value"] || "ok"
         }}
      end
    end

    defp fetch(map, key) when is_map(map) do
      Map.get(map, key, Map.get(map, Atom.to_string(key)))
    end
  end

  defmodule TestConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "dispatch_test",
        capabilities: [
          Capability.new!(%{
            id: "dispatch_test.async.echo",
            connector: "dispatch_test",
            runtime_class: :direct,
            kind: :operation,
            transport_profile: :async_trigger,
            handler: ScriptedCapability,
            metadata: %{}
          })
        ]
      })
    end
  end

  defmodule ExecuteTriggerHandler do
    @behaviour Jido.Integration.V2.DispatchRuntime.Handler

    @impl true
    def execution_opts(trigger, %{attempt: attempt}) do
      {:ok,
       [
         actor_id: "dispatch-runtime-test",
         tenant_id: trigger.tenant_id,
         allowed_operations: [trigger.capability_id],
         aggregator_id: "dispatch_runtime_test",
         aggregator_epoch: attempt,
         trace_id: "dispatch-runtime-attempt-#{attempt}"
       ]}
    end
  end

  setup do
    storage_dir = tmp_dir!()
    ControlPlane.reset!()
    assert :ok = ControlPlane.register_connector(TestConnector)

    on_exit(fn ->
      ControlPlane.reset!()
      File.rm_rf!(storage_dir)
    end)

    %{storage_dir: storage_dir}
  end

  test "emits redacted telemetry for enqueue and delivery", %{storage_dir: storage_dir} do
    {:ok, runtime} = start_runtime(storage_dir)
    assert :ok = DispatchRuntime.register_handler(runtime, "desk.alert", ExecuteTriggerHandler)

    attach_telemetry!(
      [
        DispatchTelemetry.event(:enqueue),
        DispatchTelemetry.event(:deliver)
      ],
      "dispatch-runtime-telemetry"
    )

    trigger =
      trigger_fixture("delivery-telemetry", %{
        "authorization" => "Bearer dispatch-secret",
        "nested" => %{"client_secret" => "nested-secret"},
        "value" => "ok"
      })

    assert {:ok, %{dispatch: dispatch, run: run}} =
             DispatchRuntime.enqueue(runtime, trigger, max_attempts: 2)

    assert_receive {:telemetry_event, event, %{count: 1}, metadata}, 1_000
    assert event == DispatchTelemetry.event(:enqueue)
    assert metadata.dispatch_id == dispatch.dispatch_id
    assert metadata.run_id == run.run_id
    assert metadata.status == :accepted
    assert metadata.trigger.payload["authorization"] == Redaction.redacted()
    assert metadata.trigger.payload["nested"]["client_secret"] == Redaction.redacted()
    refute inspect(metadata) =~ "dispatch-secret"
    refute inspect(metadata) =~ "nested-secret"

    completed_dispatch =
      wait_for_dispatch(runtime, dispatch.dispatch_id, &(&1.status == :completed))

    assert completed_dispatch.attempts == 1

    assert_receive {:telemetry_event, event, %{attempt: 1}, metadata}, 1_000
    assert event == DispatchTelemetry.event(:deliver)
    assert metadata.dispatch_id == dispatch.dispatch_id
    assert metadata.run_id == run.run_id
    assert metadata.status == :completed
    assert metadata.attempts == 1
  end

  test "emits retry, dead-letter, and replay telemetry with backoff measurements", %{
    storage_dir: storage_dir
  } do
    {:ok, runtime} = start_runtime(storage_dir, backoff_base_ms: 10, backoff_cap_ms: 10)
    assert :ok = DispatchRuntime.register_handler(runtime, "desk.alert", ExecuteTriggerHandler)

    attach_telemetry!(
      [
        DispatchTelemetry.event(:retry),
        DispatchTelemetry.event(:dead_letter),
        DispatchTelemetry.event(:replay)
      ],
      "dispatch-runtime-pressure"
    )

    trigger =
      trigger_fixture("delivery-pressure", %{
        "api_token" => "dispatch-token",
        "fail_attempts" => 2,
        "value" => "replayed"
      })

    assert {:ok, %{dispatch: dispatch}} =
             DispatchRuntime.enqueue(runtime, trigger, max_attempts: 2)

    dead_lettered_dispatch =
      wait_for_dispatch(runtime, dispatch.dispatch_id, &(&1.status == :dead_lettered))

    assert dead_lettered_dispatch.attempts == 2

    assert_receive {:telemetry_event, event, %{attempt: 1, backoff_ms: 10}, metadata}, 1_000
    assert event == DispatchTelemetry.event(:retry)
    assert metadata.dispatch_id == dispatch.dispatch_id
    assert metadata.status == :retry_scheduled
    assert metadata.attempts == 1
    assert metadata.trigger.payload["api_token"] == Redaction.redacted()
    refute inspect(metadata) =~ "dispatch-token"

    assert_receive {:telemetry_event, event, %{attempts: 2}, metadata}, 1_000
    assert event == DispatchTelemetry.event(:dead_letter)
    assert metadata.dispatch_id == dispatch.dispatch_id
    assert metadata.status == :dead_lettered
    assert metadata.last_error.reason == "{:scripted_failure, 2}"

    assert {:ok, replayed_dispatch} = DispatchRuntime.replay(runtime, dispatch.dispatch_id)
    assert replayed_dispatch.status in [:queued, :retry_scheduled, :running]

    assert_receive {:telemetry_event, event, %{attempts: 2}, metadata}, 1_000
    assert event == DispatchTelemetry.event(:replay)
    assert metadata.dispatch_id == dispatch.dispatch_id
    assert metadata.attempts == 2

    completed_dispatch =
      wait_for_dispatch(runtime, dispatch.dispatch_id, &(&1.status == :completed))

    assert completed_dispatch.attempts == 3
  end

  test "enqueue accepts work durably and exposes stable query APIs", %{storage_dir: storage_dir} do
    {:ok, runtime} = start_runtime(storage_dir)
    trigger = trigger_fixture("delivery-durable")

    assert {:ok, %{status: :accepted, dispatch: %Dispatch{} = dispatch, run: %Run{} = run}} =
             DispatchRuntime.enqueue(runtime, trigger, max_attempts: 3)

    assert dispatch.status == :queued
    assert dispatch.run_id == run.run_id
    assert dispatch.attempts == 0

    assert {:ok, ^dispatch} = DispatchRuntime.fetch_dispatch(runtime, dispatch.dispatch_id)
    assert [listed_dispatch] = DispatchRuntime.list_dispatches(runtime, status: :queued)
    assert listed_dispatch.dispatch_id == dispatch.dispatch_id
    assert [run_dispatch] = DispatchRuntime.list_dispatches(runtime, run_id: run.run_id)
    assert run_dispatch.dispatch_id == dispatch.dispatch_id

    assert {:ok, %Run{status: :accepted}} = ControlPlane.fetch_run(run.run_id)
    assert :error = ControlPlane.fetch_attempt("#{run.run_id}:1")

    stop_runtime(runtime)

    {:ok, restarted} = start_runtime(storage_dir)

    assert {:ok, restored_dispatch} =
             DispatchRuntime.fetch_dispatch(restarted, dispatch.dispatch_id)

    assert restored_dispatch.status == :queued
    assert restored_dispatch.run_id == run.run_id
  end

  test "duplicate and already-bound work behave deterministically", %{storage_dir: storage_dir} do
    {:ok, runtime} = start_runtime(storage_dir)
    trigger = trigger_fixture("delivery-duplicate")

    assert {:ok, %{status: :accepted, dispatch: dispatch, run: run}} =
             DispatchRuntime.enqueue(runtime, trigger, max_attempts: 2)

    already_bound = %{trigger | run_id: run.run_id}

    assert {:ok, %{status: :duplicate, dispatch: duplicate_dispatch, run: duplicate_run}} =
             DispatchRuntime.enqueue(runtime, already_bound, max_attempts: 2)

    assert duplicate_dispatch.dispatch_id == dispatch.dispatch_id
    assert duplicate_dispatch.run_id == run.run_id
    assert duplicate_run.run_id == run.run_id
    assert [listed_dispatch] = DispatchRuntime.list_dispatches(runtime, run_id: run.run_id)
    assert listed_dispatch.dispatch_id == dispatch.dispatch_id
  end

  test "worker execution records attempt and run outcomes through the control plane", %{
    storage_dir: storage_dir
  } do
    {:ok, runtime} = start_runtime(storage_dir)
    assert :ok = DispatchRuntime.register_handler(runtime, "desk.alert", ExecuteTriggerHandler)

    trigger = trigger_fixture("delivery-success", %{"test_pid" => self(), "value" => "done"})

    assert {:ok, %{dispatch: dispatch, run: run}} =
             DispatchRuntime.enqueue(runtime, trigger, max_attempts: 2)

    run_id = run.run_id

    assert_receive {:capability_attempt, ^run_id, 1}, 1_000

    completed_dispatch =
      wait_for_dispatch(runtime, dispatch.dispatch_id, &(&1.status == :completed))

    assert completed_dispatch.attempts == 1
    assert {:ok, %Run{status: :completed}} = ControlPlane.fetch_run(run.run_id)

    assert {:ok, %Attempt{attempt: 1, status: :completed} = attempt} =
             ControlPlane.fetch_attempt("#{run.run_id}:1")

    assert attempt.aggregator_id == "dispatch_runtime_test"
    assert attempt.aggregator_epoch == 1

    assert [
             %{attempt: nil, seq: 0, type: "run.accepted"},
             %{attempt: 1, seq: 0, type: "run.started"},
             %{attempt: 1, seq: 1, type: "attempt.started"},
             %{attempt: 1, seq: 2, type: "attempt.completed"},
             %{attempt: 1, seq: 3, type: "run.completed"}
           ] = Enum.map(ControlPlane.events(run.run_id), &Map.take(&1, [:attempt, :seq, :type]))
  end

  test "retry scheduling increments attempts and eventually completes", %{
    storage_dir: storage_dir
  } do
    {:ok, runtime} = start_runtime(storage_dir, backoff_base_ms: 10, backoff_cap_ms: 10)
    assert :ok = DispatchRuntime.register_handler(runtime, "desk.alert", ExecuteTriggerHandler)

    trigger =
      trigger_fixture("delivery-retry", %{
        "test_pid" => self(),
        "fail_attempts" => 1,
        "value" => "recovered"
      })

    assert {:ok, %{dispatch: dispatch, run: run}} =
             DispatchRuntime.enqueue(runtime, trigger, max_attempts: 3)

    run_id = run.run_id

    assert_receive {:capability_attempt, ^run_id, 1}, 1_000
    assert_receive {:capability_attempt, ^run_id, 2}, 1_000

    completed_dispatch =
      wait_for_dispatch(runtime, dispatch.dispatch_id, &(&1.status == :completed))

    assert completed_dispatch.attempts == 2
    assert is_nil(completed_dispatch.last_error)

    assert {:ok, %Attempt{attempt: 1, status: :failed}} =
             ControlPlane.fetch_attempt("#{run.run_id}:1")

    assert {:ok, %Attempt{attempt: 2, status: :completed}} =
             ControlPlane.fetch_attempt("#{run.run_id}:2")

    assert {:ok, %Run{status: :completed}} = ControlPlane.fetch_run(run.run_id)
  end

  test "dead-letter transition is durable across runtime restart", %{storage_dir: storage_dir} do
    {:ok, runtime} = start_runtime(storage_dir, backoff_base_ms: 10, backoff_cap_ms: 10)
    assert :ok = DispatchRuntime.register_handler(runtime, "desk.alert", ExecuteTriggerHandler)

    trigger =
      trigger_fixture("delivery-dead-letter", %{
        "test_pid" => self(),
        "fail_attempts" => 3
      })

    assert {:ok, %{dispatch: dispatch, run: run}} =
             DispatchRuntime.enqueue(runtime, trigger, max_attempts: 2)

    run_id = run.run_id

    assert_receive {:capability_attempt, ^run_id, 1}, 1_000
    assert_receive {:capability_attempt, ^run_id, 2}, 1_000

    dead_lettered_dispatch =
      wait_for_dispatch(runtime, dispatch.dispatch_id, &(&1.status == :dead_lettered))

    assert dead_lettered_dispatch.attempts == 2
    assert dead_lettered_dispatch.dead_lettered_at
    assert dead_lettered_dispatch.last_error.reason == "{:scripted_failure, 2}"
    assert {:ok, %Run{status: :failed}} = ControlPlane.fetch_run(run.run_id)

    stop_runtime(runtime)

    {:ok, restarted} = start_runtime(storage_dir)

    assert {:ok, persisted_dispatch} =
             DispatchRuntime.fetch_dispatch(restarted, dispatch.dispatch_id)

    assert persisted_dispatch.status == :dead_lettered
    assert persisted_dispatch.attempts == 2
  end

  test "replay schedules the next attempt after dead-lettered work", %{storage_dir: storage_dir} do
    {:ok, runtime} = start_runtime(storage_dir, backoff_base_ms: 10, backoff_cap_ms: 10)
    assert :ok = DispatchRuntime.register_handler(runtime, "desk.alert", ExecuteTriggerHandler)

    trigger =
      trigger_fixture("delivery-replay", %{
        "test_pid" => self(),
        "fail_attempts" => 2,
        "value" => "replayed"
      })

    assert {:ok, %{dispatch: dispatch, run: run}} =
             DispatchRuntime.enqueue(runtime, trigger, max_attempts: 2)

    dead_lettered_dispatch =
      wait_for_dispatch(runtime, dispatch.dispatch_id, &(&1.status == :dead_lettered))

    assert dead_lettered_dispatch.attempts == 2
    assert {:ok, replayed_dispatch} = DispatchRuntime.replay(runtime, dispatch.dispatch_id)
    assert replayed_dispatch.status in [:queued, :retry_scheduled, :running]

    run_id = run.run_id

    assert_receive {:capability_attempt, ^run_id, 3}, 1_000

    completed_dispatch =
      wait_for_dispatch(runtime, dispatch.dispatch_id, &(&1.status == :completed))

    assert completed_dispatch.attempts == 3

    assert {:ok, %Attempt{attempt: 3, status: :completed}} =
             ControlPlane.fetch_attempt("#{run.run_id}:3")
  end

  test "recovery after runtime restart resumes in-flight work on the next attempt", %{
    storage_dir: storage_dir
  } do
    {:ok, runtime} = start_runtime(storage_dir)
    assert :ok = DispatchRuntime.register_handler(runtime, "desk.alert", ExecuteTriggerHandler)

    trigger =
      trigger_fixture("delivery-restart", %{
        "test_pid" => self(),
        "sleep_ms" => 500,
        "value" => "after-restart"
      })

    assert {:ok, %{dispatch: dispatch, run: run}} =
             DispatchRuntime.enqueue(runtime, trigger, max_attempts: 3)

    run_id = run.run_id

    assert_receive {:capability_attempt, ^run_id, 1}, 1_000
    kill_runtime(runtime)

    {:ok, restarted} = start_runtime(storage_dir)
    assert :ok = DispatchRuntime.register_handler(restarted, "desk.alert", ExecuteTriggerHandler)

    assert_receive {:capability_attempt, ^run_id, 2}, 1_000

    completed_dispatch =
      wait_for_dispatch(restarted, dispatch.dispatch_id, &(&1.status == :completed))

    assert completed_dispatch.attempts == 2

    assert {:ok, %Attempt{attempt: 1, status: :accepted}} =
             ControlPlane.fetch_attempt("#{run.run_id}:1")

    assert {:ok, %Attempt{attempt: 2, status: :completed}} =
             ControlPlane.fetch_attempt("#{run.run_id}:2")
  end

  defp start_runtime(storage_dir, opts \\ []) do
    {:ok, runtime} =
      DispatchRuntime.start_link(
        Keyword.merge(
          [
            name: nil,
            storage_dir: storage_dir,
            max_attempts: 3,
            backoff_base_ms: 10,
            backoff_cap_ms: 20
          ],
          opts
        )
      )

    Process.unlink(runtime)

    on_exit(fn ->
      if Process.alive?(runtime) do
        stop_runtime(runtime)
      end
    end)

    {:ok, runtime}
  end

  defp stop_runtime(runtime) do
    GenServer.stop(runtime, :normal, 5_000)
  end

  defp kill_runtime(runtime) do
    ref = Process.monitor(runtime)
    GenServer.stop(runtime, :shutdown, 5_000)

    receive do
      {:DOWN, ^ref, :process, ^runtime, _reason} -> :ok
    after
      5_000 -> flunk("runtime did not terminate")
    end
  end

  defp wait_for_dispatch(runtime, dispatch_id, predicate, attempts \\ 60)

  defp wait_for_dispatch(_runtime, dispatch_id, _predicate, 0) do
    flunk("dispatch #{dispatch_id} did not reach the expected state")
  end

  defp wait_for_dispatch(runtime, dispatch_id, predicate, attempts) do
    case DispatchRuntime.fetch_dispatch(runtime, dispatch_id) do
      {:ok, %Dispatch{} = dispatch} ->
        if predicate.(dispatch) do
          dispatch
        else
          Process.sleep(25)
          wait_for_dispatch(runtime, dispatch_id, predicate, attempts - 1)
        end

      :error ->
        Process.sleep(25)
        wait_for_dispatch(runtime, dispatch_id, predicate, attempts - 1)
    end
  end

  defp trigger_fixture(dedupe_key, payload \\ %{}) do
    TriggerRecord.new!(%{
      admission_id: "trigger-#{dedupe_key}",
      source: :poll,
      connector_id: "dispatch_test",
      trigger_id: "desk.alert",
      capability_id: "dispatch_test.async.echo",
      tenant_id: "tenant-1",
      external_id: dedupe_key,
      dedupe_key: dedupe_key,
      payload: payload,
      signal: %{"type" => "dispatch.test.trigger", "source" => "/dispatch/test"}
    })
  end

  defp tmp_dir! do
    TestTmpDir.create!("jido_dispatch_runtime_test")
  end

  defp attach_telemetry!(events, prefix) do
    handler_id = "#{prefix}-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  def handle_telemetry_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end
end
