defmodule Jido.Integration.Dispatch.DurableConsumerTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Jido.Integration.Dispatch.Consumer
  alias Jido.Integration.Dispatch.{RunStore, Store}

  import Jido.Integration.Test.IsolatedSetup, only: [wait_for_run: 3]

  defmodule SlowSuccessHandler do
    def handle_trigger(%{"test_pid" => test_pid, "sleep_ms" => sleep_ms}, context) do
      send(test_pid, {:attempt_started, context.run_id, context.attempt})
      Process.sleep(sleep_ms)
      {:ok, %{"attempt" => context.attempt}}
    end
  end

  defmodule SuccessHandler do
    def handle_trigger(_payload, context) do
      {:ok, %{"attempt" => context.attempt}}
    end
  end

  defmodule FailHandler do
    def handle_trigger(_payload, _context) do
      {:error, :boom}
    end
  end

  test "recovers a running run after consumer restart", %{tmp_dir: tmp_dir} do
    opts = durable_opts(tmp_dir)

    {:ok, consumer} = Consumer.start_link(opts)
    :ok = Consumer.register_callback(consumer, "test.trigger", SlowSuccessHandler)

    {:ok, run_id} =
      Consumer.dispatch(consumer, %{
        dispatch_id: "d_restart",
        trigger_id: "test.trigger",
        payload: %{"test_pid" => self(), "sleep_ms" => 200}
      })

    assert_receive {:attempt_started, ^run_id, 1}, 500
    ref = Process.monitor(consumer)
    Process.unlink(consumer)
    Process.exit(consumer, :kill)

    receive do
      {:DOWN, ^ref, :process, ^consumer, _} -> :ok
    after
      5_000 -> flunk("consumer did not terminate")
    end

    {:ok, restarted} = Consumer.start_link(opts)
    :ok = Consumer.register_callback(restarted, "test.trigger", SlowSuccessHandler)

    assert_receive {:attempt_started, ^run_id, 1}, 500

    run = wait_for_run(restarted, run_id, &(&1.status == :succeeded))
    assert run.result == %{"attempt" => 1}

    assert {:ok, persisted_dispatch} =
             Store.Disk.fetch(store_name(tmp_dir, :dispatch), "d_restart")

    assert persisted_dispatch.run_id == run_id

    assert {:ok, persisted_run} = RunStore.Disk.fetch(store_name(tmp_dir, :run), run_id)
    assert persisted_run.status == :succeeded
  end

  test "replays a dead-lettered run after consumer restart", %{tmp_dir: tmp_dir} do
    opts = durable_opts(tmp_dir)

    {:ok, consumer} = Consumer.start_link(opts)
    :ok = Consumer.register_callback(consumer, "test.trigger", FailHandler)

    {:ok, run_id} =
      Consumer.dispatch(consumer, %{
        dispatch_id: "d_replay_restart",
        trigger_id: "test.trigger",
        max_attempts: 1
      })

    dead_lettered = wait_for_run(consumer, run_id, &(&1.status == :dead_lettered))
    assert dead_lettered.attempt == 1

    ref = Process.monitor(consumer)
    Process.unlink(consumer)
    Process.exit(consumer, :kill)

    receive do
      {:DOWN, ^ref, :process, ^consumer, _} -> :ok
    after
      5_000 -> flunk("consumer did not terminate")
    end

    {:ok, restarted} = Consumer.start_link(opts)
    :ok = Consumer.register_callback(restarted, "test.trigger", SuccessHandler)

    assert {:ok, ^run_id} = Consumer.replay(restarted, run_id)

    replayed = wait_for_run(restarted, run_id, &(&1.status == :succeeded))
    assert replayed.attempt == 2
    assert replayed.attempt_id == "#{run_id}:2"
    assert replayed.result == %{"attempt" => 2}

    assert {:ok, persisted_dispatch} =
             Store.Disk.fetch(store_name(tmp_dir, :dispatch), "d_replay_restart")

    assert persisted_dispatch.run_id == run_id
    assert persisted_dispatch.status == :delivered

    assert {:ok, persisted_run} = RunStore.Disk.fetch(store_name(tmp_dir, :run), run_id)
    assert persisted_run.status == :succeeded
    assert persisted_run.attempt == 2
  end

  defp durable_opts(tmp_dir) do
    [
      name: nil,
      max_attempts: 2,
      backoff_base_ms: 1,
      backoff_cap_ms: 10,
      dispatch_store_module: Store.Disk,
      run_store_module: RunStore.Disk,
      dispatch_store_opts: [name: store_name(tmp_dir, :dispatch), dir: tmp_dir],
      run_store_opts: [name: store_name(tmp_dir, :run), dir: tmp_dir]
    ]
  end

  defp store_name(tmp_dir, suffix) do
    String.to_atom("durable_#{suffix}_#{:erlang.phash2(tmp_dir)}")
  end
end
