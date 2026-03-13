defmodule Jido.Integration.Dispatch.ConsumerTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Dispatch.Consumer
  alias Jido.Integration.Test.TelemetryHandler

  import Jido.Integration.Test.IsolatedSetup,
    only: [start_isolated_consumer: 1, wait_for_run: 3]

  defmodule SuccessHandler do
    def handle_trigger(event, context) do
      {:ok,
       %{
         "processed" => true,
         "input" => event,
         "dispatch_id" => context.dispatch_id,
         "attempt_id" => context.attempt_id
       }}
    end
  end

  defmodule FailHandler do
    def handle_trigger(_event, _context) do
      {:error, :processing_failed}
    end
  end

  defmodule RecordingFailHandler do
    def handle_trigger(%{"test_pid" => test_pid}, context) do
      send(test_pid, {:attempt_started, context.attempt, System.monotonic_time(:millisecond)})
      {:error, :processing_failed}
    end
  end

  defmodule OkHandler do
    def handle_trigger(_event, _context), do: :ok
  end

  defmodule CrashHandler do
    def handle_trigger(_event, _context) do
      raise "boom"
    end
  end

  defmodule InvalidHandler do
  end

  defmodule ScriptedDispatchStore do
    use GenServer

    alias Jido.Integration.Dispatch.Record

    @behaviour Jido.Integration.Dispatch.Store

    @impl true
    def start_link(opts \\ []) do
      case Keyword.fetch(opts, :name) do
        {:ok, nil} -> GenServer.start_link(__MODULE__, opts)
        {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
        :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end
    end

    @impl true
    def put(server, %Record{} = record), do: GenServer.call(server, {:put, record})

    @impl true
    def fetch(server, dispatch_id), do: GenServer.call(server, {:fetch, dispatch_id})

    @impl true
    def list(server), do: GenServer.call(server, {:list, []})

    @impl true
    def list(server, opts), do: GenServer.call(server, {:list, opts})

    @impl true
    def delete(server, dispatch_id), do: GenServer.call(server, {:delete, dispatch_id})

    @impl true
    def init(opts) do
      {:ok,
       %{
         entries: %{},
         put_count: 0,
         fail_puts: MapSet.new(Keyword.get(opts, :fail_puts, [])),
         fail_reason: Keyword.get(opts, :fail_reason, :scripted_dispatch_store_failure)
       }}
    end

    @impl true
    def handle_call({:put, %Record{} = record}, _from, state) do
      put_count = state.put_count + 1

      if MapSet.member?(state.fail_puts, put_count) do
        {:reply, {:error, state.fail_reason}, %{state | put_count: put_count}}
      else
        {:reply, :ok,
         %{
           state
           | put_count: put_count,
             entries: Map.put(state.entries, record.dispatch_id, record)
         }}
      end
    end

    @impl true
    def handle_call({:fetch, dispatch_id}, _from, state) do
      reply =
        case Map.get(state.entries, dispatch_id) do
          nil -> {:error, :not_found}
          record -> {:ok, record}
        end

      {:reply, reply, state}
    end

    @impl true
    def handle_call({:list, opts}, _from, state) do
      {:reply, state.entries |> Map.values() |> filter_dispatches(opts), state}
    end

    @impl true
    def handle_call({:delete, dispatch_id}, _from, state) do
      if Map.has_key?(state.entries, dispatch_id) do
        {:reply, :ok, %{state | entries: Map.delete(state.entries, dispatch_id)}}
      else
        {:reply, {:error, :not_found}, state}
      end
    end

    defp filter_dispatches(records, opts) do
      Enum.filter(records, fn record ->
        matches_filter?(record.status, Keyword.get(opts, :status), Keyword.get(opts, :statuses)) and
          matches_value?(record.tenant_id, Keyword.get(opts, :tenant_id)) and
          matches_value?(record.connector_id, Keyword.get(opts, :connector_id)) and
          matches_value?(record.trigger_id, Keyword.get(opts, :trigger_id)) and
          matches_value?(record.idempotency_key, Keyword.get(opts, :idempotency_key)) and
          matches_value?(record.dispatch_id, Keyword.get(opts, :dispatch_id)) and
          matches_value?(record.run_id, Keyword.get(opts, :run_id))
      end)
    end

    defp matches_filter?(_value, nil, nil), do: true
    defp matches_filter?(value, expected, nil), do: value == expected
    defp matches_filter?(value, nil, expected_values), do: value in expected_values

    defp matches_filter?(value, expected, expected_values),
      do: value == expected and value in expected_values

    defp matches_value?(_value, nil), do: true
    defp matches_value?(value, expected), do: value == expected
  end

  defmodule ScriptedRunStore do
    use GenServer

    alias Jido.Integration.Dispatch.Run

    @behaviour Jido.Integration.Dispatch.RunStore

    @impl true
    def start_link(opts \\ []) do
      case Keyword.fetch(opts, :name) do
        {:ok, nil} -> GenServer.start_link(__MODULE__, opts)
        {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
        :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end
    end

    @impl true
    def put(server, %Run{} = run), do: GenServer.call(server, {:put, run})

    @impl true
    def fetch(server, run_id), do: GenServer.call(server, {:fetch, run_id})

    @impl true
    def fetch_by_idempotency(server, idempotency_key),
      do: GenServer.call(server, {:fetch_by_idempotency, idempotency_key})

    @impl true
    def list(server), do: GenServer.call(server, {:list, []})

    @impl true
    def list(server, opts), do: GenServer.call(server, {:list, opts})

    @impl true
    def delete(server, run_id), do: GenServer.call(server, {:delete, run_id})

    @impl true
    def init(opts) do
      {:ok,
       %{
         entries: %{},
         idempotency_index: %{},
         put_count: 0,
         fail_puts: MapSet.new(Keyword.get(opts, :fail_puts, [])),
         fail_reason: Keyword.get(opts, :fail_reason, :scripted_run_store_failure)
       }}
    end

    @impl true
    def handle_call({:put, %Run{} = run}, _from, state) do
      put_count = state.put_count + 1

      cond do
        MapSet.member?(state.fail_puts, put_count) ->
          {:reply, {:error, state.fail_reason}, %{state | put_count: put_count}}

        conflict_run_id = conflicting_run_id(state, run) ->
          {:reply, {:error, {:idempotency_conflict, conflict_run_id}},
           %{state | put_count: put_count}}

        true ->
          {:reply, :ok,
           %{
             state
             | put_count: put_count,
               entries: Map.put(state.entries, run.run_id, run),
               idempotency_index:
                 Map.put(state.idempotency_index, run.idempotency_key, run.run_id)
           }}
      end
    end

    @impl true
    def handle_call({:fetch, run_id}, _from, state) do
      reply =
        case Map.get(state.entries, run_id) do
          nil -> {:error, :not_found}
          run -> {:ok, run}
        end

      {:reply, reply, state}
    end

    @impl true
    def handle_call({:fetch_by_idempotency, idempotency_key}, _from, state) do
      reply =
        case Map.get(state.idempotency_index, idempotency_key) do
          nil -> {:error, :not_found}
          run_id -> {:ok, Map.fetch!(state.entries, run_id)}
        end

      {:reply, reply, state}
    end

    @impl true
    def handle_call({:list, opts}, _from, state) do
      {:reply, state.entries |> Map.values() |> filter_runs(opts), state}
    end

    @impl true
    def handle_call({:delete, run_id}, _from, state) do
      case Map.pop(state.entries, run_id) do
        {nil, _entries} ->
          {:reply, {:error, :not_found}, state}

        {%Run{} = run, entries} ->
          idempotency_index =
            case Map.get(state.idempotency_index, run.idempotency_key) do
              ^run_id -> Map.delete(state.idempotency_index, run.idempotency_key)
              _ -> state.idempotency_index
            end

          {:reply, :ok, %{state | entries: entries, idempotency_index: idempotency_index}}
      end
    end

    defp conflicting_run_id(state, %Run{} = run) do
      case Map.get(state.idempotency_index, run.idempotency_key) do
        nil -> nil
        existing_run_id when existing_run_id == run.run_id -> nil
        existing_run_id -> existing_run_id
      end
    end

    defp filter_runs(records, opts) do
      Enum.filter(records, fn run ->
        matches_filter?(run.status, Keyword.get(opts, :status), Keyword.get(opts, :statuses)) and
          matches_value?(run.tenant_id, Keyword.get(opts, :tenant_id)) and
          matches_value?(run.connector_id, Keyword.get(opts, :connector_id)) and
          matches_value?(run.trigger_id, Keyword.get(opts, :trigger_id)) and
          matches_value?(run.callback_id, Keyword.get(opts, :callback_id)) and
          matches_value?(run.dispatch_id, Keyword.get(opts, :dispatch_id)) and
          matches_value?(run.idempotency_key, Keyword.get(opts, :idempotency_key))
      end)
    end

    defp matches_filter?(_value, nil, nil), do: true
    defp matches_filter?(value, expected, nil), do: value == expected
    defp matches_filter?(value, nil, expected_values), do: value in expected_values

    defp matches_filter?(value, expected, expected_values),
      do: value == expected and value in expected_values

    defp matches_value?(_value, nil), do: true
    defp matches_value?(value, expected), do: value == expected
  end

  setup do
    {:ok, consumer} =
      start_isolated_consumer(max_attempts: 3, backoff_base_ms: 1, backoff_cap_ms: 10)

    %{consumer: consumer}
  end

  describe "register_callback/3" do
    test "registers a callback module", %{consumer: consumer} do
      assert :ok = Consumer.register_callback(consumer, "test.trigger", SuccessHandler)
    end

    test "rejects modules without handle_trigger/2", %{consumer: consumer} do
      assert {:error, :invalid_callback_module} =
               Consumer.register_callback(consumer, "test.trigger", InvalidHandler)
    end
  end

  describe "dispatch/2" do
    test "accepts a dispatch record and returns a UUID run_id", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_1",
          trigger_id: "test.trigger",
          tenant_id: "acme",
          connector_id: "test",
          payload: %{"data" => "hello"}
        })

      assert run_id =~
               ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
    end

    test "idempotency check returns duplicate for same key", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_2",
          trigger_id: "test.trigger",
          idempotency_key: "idem_1"
        })

      {:duplicate, same_run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_3",
          trigger_id: "test.trigger",
          idempotency_key: "idem_1"
        })

      assert run_id == same_run_id
    end

    test "defaults idempotency_key to dispatch_id", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      {:ok, _} = Consumer.dispatch(consumer, %{dispatch_id: "d_same", trigger_id: "test.trigger"})

      assert {:duplicate, _} =
               Consumer.dispatch(consumer, %{dispatch_id: "d_same", trigger_id: "test.trigger"})
    end

    test "requires dispatch_id", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      assert {:error, :dispatch_id_required} =
               Consumer.dispatch(consumer, %{trigger_id: "test.trigger"})
    end

    test "requires trigger_id", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      assert {:error, :trigger_id_required} =
               Consumer.dispatch(consumer, %{dispatch_id: "d_missing"})
    end

    test "requires payload to be a map", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      assert {:error, :payload_must_be_map} =
               Consumer.dispatch(consumer, %{
                 dispatch_id: "d_bad_payload",
                 trigger_id: "test.trigger",
                 payload: "nope"
               })
    end

    test "fails fast when no callback is registered", %{consumer: consumer} do
      assert {:error, :no_callback_registered} =
               Consumer.dispatch(consumer, %{
                 dispatch_id: "d_no_cb",
                 trigger_id: "unregistered.trigger"
               })

      assert Consumer.list_runs(consumer) == []
    end

    test "concurrent duplicate dispatches share one run_id", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      results =
        1..5
        |> Task.async_stream(
          fn idx ->
            Consumer.dispatch(consumer, %{
              dispatch_id: "d_concurrent_#{idx}",
              trigger_id: "test.trigger",
              idempotency_key: "idem_concurrent"
            })
          end,
          timeout: 1_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      run_ids =
        Enum.map(results, fn
          {:ok, run_id} -> run_id
          {:duplicate, run_id} -> run_id
        end)

      assert Enum.uniq(run_ids) |> length() == 1
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:duplicate, _}, &1)) == 4
    end

    test "returns an error when the dispatch store cannot durably persist the queued record" do
      dispatch_store = unique_name(:scripted_dispatch)
      run_store = unique_name(:scripted_run)

      {:ok, consumer} =
        Consumer.start_link(
          name: nil,
          dispatch_store_module: ScriptedDispatchStore,
          run_store_module: ScriptedRunStore,
          dispatch_store_opts: [
            name: dispatch_store,
            fail_puts: [1],
            fail_reason: :dispatch_store_down
          ],
          run_store_opts: [name: run_store]
        )

      :ok = Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      assert {:error, {:dispatch_store_put_failed, :dispatch_store_down}} =
               Consumer.dispatch(consumer, %{
                 dispatch_id: "d_store_fail",
                 trigger_id: "test.trigger"
               })

      assert [] = Consumer.list_runs(consumer)
      assert [] = ScriptedDispatchStore.list(dispatch_store)
      assert [] = ScriptedRunStore.list(run_store)
    end

    test "returns an error when the run store cannot durably persist the accepted run and leaves queued dispatch recoverable" do
      dispatch_store = unique_name(:scripted_dispatch)
      run_store = unique_name(:scripted_run)

      {:ok, consumer} =
        Consumer.start_link(
          name: nil,
          dispatch_store_module: ScriptedDispatchStore,
          run_store_module: ScriptedRunStore,
          dispatch_store_opts: [name: dispatch_store],
          run_store_opts: [name: run_store, fail_puts: [1], fail_reason: :run_store_down]
        )

      :ok = Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      assert {:error, {:run_store_put_failed, :run_store_down}} =
               Consumer.dispatch(consumer, %{
                 dispatch_id: "d_run_fail",
                 trigger_id: "test.trigger"
               })

      assert [] = Consumer.list_runs(consumer)
      assert {:ok, queued_dispatch} = ScriptedDispatchStore.fetch(dispatch_store, "d_run_fail")
      assert queued_dispatch.status == :queued
      assert [] = ScriptedRunStore.list(run_store)
    end

    test "rolls back the accepted run when the dispatch store cannot persist the delivered state" do
      dispatch_store = unique_name(:scripted_dispatch)
      run_store = unique_name(:scripted_run)

      {:ok, consumer} =
        Consumer.start_link(
          name: nil,
          dispatch_store_module: ScriptedDispatchStore,
          run_store_module: ScriptedRunStore,
          dispatch_store_opts: [
            name: dispatch_store,
            fail_puts: [2],
            fail_reason: :dispatch_store_second_put_failed
          ],
          run_store_opts: [name: run_store]
        )

      :ok = Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      assert {:error, {:dispatch_store_put_failed, :dispatch_store_second_put_failed}} =
               Consumer.dispatch(
                 consumer,
                 %{dispatch_id: "d_delivered_fail", trigger_id: "test.trigger"}
               )

      assert [] = Consumer.list_runs(consumer)

      assert {:ok, queued_dispatch} =
               ScriptedDispatchStore.fetch(dispatch_store, "d_delivered_fail")

      assert queued_dispatch.status == :queued
      assert [] = ScriptedRunStore.list(run_store)
    end
  end

  describe "execution lifecycle" do
    test "successful dispatch transitions to :succeeded with run metadata", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_success",
          trigger_id: "test.trigger",
          tenant_id: "acme",
          connector_id: "test",
          payload: %{"value" => 42},
          trace_context: %{trace_id: "t_123", span_id: "s_456", correlation_id: "c_789"}
        })

      run = wait_for_run(consumer, run_id, &(&1.status == :succeeded))

      assert run.status == :succeeded
      assert run.result["processed"] == true
      assert run.result["input"] == %{"value" => 42}
      assert run.result["dispatch_id"] == "d_success"
      assert run.attempt == 1
      assert run.attempt_id == "#{run_id}:1"
      assert run.callback_id == inspect(SuccessHandler)
      assert %DateTime{} = run.accepted_at
      assert %DateTime{} = run.started_at
      assert %DateTime{} = run.finished_at
      assert run.trace_context.trace_id == "t_123"
      assert run.trace_context.span_id == "s_456"
      assert run.trace_context.correlation_id == "c_789"
      assert run.trace_context.causation_id == "d_success"
    end

    test ":ok return is normalized to empty map result", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", OkHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{dispatch_id: "d_ok", trigger_id: "test.trigger"})

      run = wait_for_run(consumer, run_id, &(&1.status == :succeeded))
      assert run.result == %{}
    end

    test "failed dispatch retries and eventually dead-letters", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", FailHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_fail",
          trigger_id: "test.trigger",
          max_attempts: 2
        })

      run = wait_for_run(consumer, run_id, &(&1.status == :dead_lettered))

      assert run.status == :dead_lettered
      assert run.attempt == 2
      assert run.attempt_id == "#{run_id}:2"
      assert run.error_context == %{"error" => "processing_failed"}
      assert %DateTime{} = run.finished_at
    end

    test "run stays failed during retry backoff before the next attempt", _context do
      {:ok, consumer} =
        start_isolated_consumer(max_attempts: 2, backoff_base_ms: 200, backoff_cap_ms: 200)

      Consumer.register_callback(consumer, "test.trigger", RecordingFailHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_backoff",
          trigger_id: "test.trigger",
          payload: %{"test_pid" => self()}
        })

      assert_receive {:attempt_started, 1, _}, 500

      failed_run = wait_for_run(consumer, run_id, &(&1.status == :failed))
      assert failed_run.attempt == 1

      # Backoff is 200ms, so attempt 2 must NOT arrive within 50ms
      refute_receive {:attempt_started, 2, _}, 50
      assert_receive {:attempt_started, 2, _}, 500

      dead_lettered = wait_for_run(consumer, run_id, &(&1.status == :dead_lettered))
      assert dead_lettered.attempt == 2
    end

    test "crash in callback is caught and treated as failure", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", CrashHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_crash",
          trigger_id: "test.trigger",
          max_attempts: 1
        })

      run = wait_for_run(consumer, run_id, &(&1.status == :dead_lettered))
      assert run.error_context["exception"] =~ "boom"
      assert run.error_context["stacktrace"] =~ "boom"
    end
  end

  describe "telemetry" do
    test "success path emits canonical dispatch and run events with required metadata", %{
      consumer: consumer
    } do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)
      attach_ref = "dispatch-success-#{System.unique_integer([:positive])}"

      :ok =
        TelemetryHandler.attach_many(
          attach_ref,
          [
            [:jido, :integration, :dispatch, :enqueued],
            [:jido, :integration, :dispatch, :delivered],
            [:jido, :integration, :run, :accepted],
            [:jido, :integration, :run, :started],
            [:jido, :integration, :run, :succeeded],
            [:jido, :integration, :dispatch_stub, :accepted],
            [:jido, :integration, :dispatch_stub, :started],
            [:jido, :integration, :dispatch_stub, :succeeded]
          ],
          recipient: self(),
          include: [:event, :measurements, :metadata]
        )

      on_exit(fn -> :telemetry.detach(attach_ref) end)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_tel_success",
          trigger_id: "test.trigger",
          tenant_id: "acme",
          connector_id: "github",
          trace_context: %{trace_id: "trace", span_id: "span", correlation_id: "corr"}
        })

      attempt_id_1 = "#{run_id}:1"

      assert_receive {:telemetry, [:jido, :integration, :dispatch, :enqueued], _,
                      %{
                        run_id: nil,
                        dispatch_id: "d_tel_success",
                        tenant_id: "acme",
                        connector_id: "github",
                        trigger_id: "test.trigger",
                        attempt: 0,
                        trace_id: "trace",
                        span_id: "span",
                        correlation_id: "corr"
                      }},
                     500

      assert_receive {:telemetry, [:jido, :integration, :dispatch, :delivered], _,
                      %{
                        run_id: ^run_id,
                        dispatch_id: "d_tel_success",
                        tenant_id: "acme",
                        connector_id: "github",
                        trigger_id: "test.trigger",
                        callback_id: callback_id,
                        attempt: 1,
                        trace_id: "trace",
                        span_id: "span",
                        correlation_id: "corr"
                      }},
                     500

      assert_receive {:telemetry, [:jido, :integration, :run, :accepted], _,
                      %{
                        run_id: ^run_id,
                        attempt_id: ^attempt_id_1,
                        dispatch_id: "d_tel_success",
                        tenant_id: "acme",
                        connector_id: "github",
                        trigger_id: "test.trigger",
                        callback_id: ^callback_id,
                        attempt: 1,
                        trace_id: "trace",
                        span_id: "span",
                        correlation_id: "corr"
                      }},
                     500

      assert_receive {:telemetry, [:jido, :integration, :run, :started], _,
                      %{
                        run_id: ^run_id,
                        attempt_id: ^attempt_id_1,
                        dispatch_id: "d_tel_success",
                        attempt: 1
                      }},
                     500

      assert_receive {:telemetry, [:jido, :integration, :run, :succeeded], _,
                      %{
                        run_id: ^run_id,
                        attempt_id: ^attempt_id_1,
                        dispatch_id: "d_tel_success",
                        attempt: 1
                      }},
                     500

      # Transitional compatibility alias only.
      assert_receive {:telemetry, [:jido, :integration, :dispatch_stub, :accepted], _,
                      %{run_id: ^run_id, dispatch_id: "d_tel_success"}},
                     500

      assert callback_id == inspect(SuccessHandler)

      assert_receive {:telemetry, [:jido, :integration, :dispatch_stub, :started], _,
                      %{run_id: ^run_id}},
                     500

      assert_receive {:telemetry, [:jido, :integration, :dispatch_stub, :succeeded], _,
                      %{run_id: ^run_id}},
                     500
    end

    test "failure and replay paths emit canonical dispatch and run events", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", FailHandler)
      attach_ref = "dispatch-failure-#{System.unique_integer([:positive])}"

      :ok =
        TelemetryHandler.attach_many(
          attach_ref,
          [
            [:jido, :integration, :dispatch, :dead_lettered],
            [:jido, :integration, :dispatch, :replayed],
            [:jido, :integration, :run, :failed],
            [:jido, :integration, :run, :dead_lettered],
            [:jido, :integration, :run, :accepted],
            [:jido, :integration, :dispatch_stub, :failed],
            [:jido, :integration, :dispatch_stub, :dead_lettered],
            [:jido, :integration, :dispatch_stub, :accepted]
          ],
          recipient: self(),
          include: [:event, :measurements, :metadata]
        )

      on_exit(fn -> :telemetry.detach(attach_ref) end)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_tel_fail",
          trigger_id: "test.trigger",
          max_attempts: 1
        })

      attempt_id_1 = "#{run_id}:1"

      assert_receive {:telemetry, [:jido, :integration, :run, :accepted], _,
                      %{run_id: ^run_id, attempt_id: ^attempt_id_1, attempt: 1}},
                     500

      assert_receive {:telemetry, [:jido, :integration, :run, :failed], _,
                      %{run_id: ^run_id, attempt_id: ^attempt_id_1, attempt: 1}},
                     500

      assert_receive {:telemetry, [:jido, :integration, :run, :dead_lettered], _,
                      %{run_id: ^run_id, attempt_id: ^attempt_id_1, attempt: 1}},
                     500

      assert_receive {:telemetry, [:jido, :integration, :dispatch, :dead_lettered], _,
                      %{run_id: ^run_id, dispatch_id: "d_tel_fail", attempt: 1}},
                     500

      # Transitional compatibility alias only.
      assert_receive {:telemetry, [:jido, :integration, :dispatch_stub, :failed], _,
                      %{run_id: ^run_id, attempt: 1}},
                     500

      assert_receive {:telemetry, [:jido, :integration, :dispatch_stub, :dead_lettered], _,
                      %{run_id: ^run_id, attempt: 1}},
                     500

      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)
      assert {:ok, ^run_id} = Consumer.replay(consumer, run_id)

      attempt_id_2 = "#{run_id}:2"

      assert_receive {:telemetry, [:jido, :integration, :dispatch, :replayed], _,
                      %{run_id: ^run_id, dispatch_id: "d_tel_fail", attempt: 2}},
                     500

      assert_receive {:telemetry, [:jido, :integration, :run, :accepted], _,
                      %{run_id: ^run_id, attempt_id: ^attempt_id_2, attempt: 2}},
                     500

      assert_receive {:telemetry, [:jido, :integration, :dispatch_stub, :accepted], _,
                      %{run_id: ^run_id, attempt: 2}},
                     500
    end
  end

  describe "dispatch visibility" do
    test "gets a dispatch record by dispatch_id", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_visible",
          trigger_id: "test.trigger",
          tenant_id: "acme",
          connector_id: "github"
        })

      dispatch = wait_for_dispatch(consumer, "d_visible", &(&1.run_id == run_id))

      assert dispatch.dispatch_id == "d_visible"
      assert dispatch.run_id == run_id
      assert dispatch.status == :delivered
      assert dispatch.tenant_id == "acme"
      assert dispatch.connector_id == "github"
    end

    test "lists dispatch records filtered by status and scope", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)
      Consumer.register_callback(consumer, "fail.trigger", FailHandler)

      {:ok, success_run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_dispatch_ok",
          trigger_id: "test.trigger",
          tenant_id: "tenant-ok",
          connector_id: "github"
        })

      {:ok, failed_run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_dispatch_fail",
          trigger_id: "fail.trigger",
          tenant_id: "tenant-fail",
          connector_id: "slack",
          max_attempts: 1
        })

      wait_for_run(consumer, success_run_id, &(&1.status == :succeeded))
      wait_for_run(consumer, failed_run_id, &(&1.status == :dead_lettered))

      [ok_dispatch] = Consumer.list_dispatches(consumer, tenant_id: "tenant-ok")
      [dead_dispatch] = Consumer.list_dispatches(consumer, status: :dead_lettered)
      [slack_dispatch] = Consumer.list_dispatches(consumer, connector_id: "slack")

      assert ok_dispatch.dispatch_id == "d_dispatch_ok"
      assert dead_dispatch.dispatch_id == "d_dispatch_fail"
      assert slack_dispatch.dispatch_id == "d_dispatch_fail"
    end
  end

  describe "get_run/2" do
    test "returns :not_found for unknown run_id", %{consumer: consumer} do
      assert {:error, :not_found} = Consumer.get_run(consumer, "run_nonexistent")
    end
  end

  describe "get_dispatch/2" do
    test "returns :not_found for unknown dispatch_id", %{consumer: consumer} do
      assert {:error, :not_found} = Consumer.get_dispatch(consumer, "dispatch_nonexistent")
    end
  end

  describe "list_runs/2" do
    test "lists all runs", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      {:ok, run_1} =
        Consumer.dispatch(consumer, %{dispatch_id: "d_list_1", trigger_id: "test.trigger"})

      {:ok, run_2} =
        Consumer.dispatch(consumer, %{dispatch_id: "d_list_2", trigger_id: "test.trigger"})

      wait_for_run(consumer, run_1, &(&1.status == :succeeded))
      wait_for_run(consumer, run_2, &(&1.status == :succeeded))

      runs = Consumer.list_runs(consumer)
      assert length(runs) == 2
    end

    test "filters by status", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)
      Consumer.register_callback(consumer, "fail.trigger", FailHandler)

      {:ok, run_s} =
        Consumer.dispatch(consumer, %{dispatch_id: "d_s", trigger_id: "test.trigger"})

      {:ok, run_f} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_f",
          trigger_id: "fail.trigger",
          max_attempts: 1
        })

      wait_for_run(consumer, run_s, &(&1.status == :succeeded))
      wait_for_run(consumer, run_f, &(&1.status == :dead_lettered))

      succeeded = Consumer.list_runs(consumer, status: :succeeded)
      dead = Consumer.list_runs(consumer, status: :dead_lettered)

      assert length(succeeded) == 1
      assert length(dead) == 1
    end

    test "filters by connector, tenant, trigger, callback, dispatch_id, and idempotency_key", %{
      consumer: consumer
    } do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_scope",
          trigger_id: "test.trigger",
          tenant_id: "tenant-scope",
          connector_id: "github",
          idempotency_key: "idem-scope"
        })

      run = wait_for_run(consumer, run_id, &(&1.status == :succeeded))

      assert [^run] = Consumer.list_runs(consumer, connector_id: "github")
      assert [^run] = Consumer.list_runs(consumer, tenant_id: "tenant-scope")
      assert [^run] = Consumer.list_runs(consumer, trigger_id: "test.trigger")
      assert [^run] = Consumer.list_runs(consumer, callback_id: inspect(SuccessHandler))
      assert [^run] = Consumer.list_runs(consumer, dispatch_id: "d_scope")
      assert [^run] = Consumer.list_runs(consumer, idempotency_key: "idem-scope")
      assert [] = Consumer.list_runs(consumer, connector_id: "slack")
    end
  end

  describe "replay/2" do
    test "replays a dead-lettered run on a new attempt", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", FailHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_replay",
          trigger_id: "test.trigger",
          max_attempts: 1
        })

      run = wait_for_run(consumer, run_id, &(&1.status == :dead_lettered))
      assert run.attempt == 1

      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)
      assert {:ok, ^run_id} = Consumer.replay(consumer, run_id)

      replayed = wait_for_run(consumer, run_id, &(&1.status == :succeeded))
      assert replayed.attempt == 2
      assert replayed.attempt_id == "#{run_id}:2"
    end

    test "cannot replay a non-dead-lettered run", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{dispatch_id: "d_no_replay", trigger_id: "test.trigger"})

      wait_for_run(consumer, run_id, &(&1.status == :succeeded))
      assert {:error, {:invalid_status, :succeeded}} = Consumer.replay(consumer, run_id)
    end

    test "replay of unknown run returns not_found", %{consumer: consumer} do
      assert {:error, :not_found} = Consumer.replay(consumer, "run_unknown")
    end
  end

  describe "trace context" do
    test "preserves trace context and sets causation_id from dispatch_id", %{consumer: consumer} do
      Consumer.register_callback(consumer, "test.trigger", SuccessHandler)

      {:ok, run_id} =
        Consumer.dispatch(consumer, %{
          dispatch_id: "d_trace",
          trigger_id: "test.trigger",
          trace_context: %{trace_id: "t_123", span_id: "s_456", correlation_id: "c_789"}
        })

      run = wait_for_run(consumer, run_id, &(&1.status == :succeeded))

      assert run.trace_context.trace_id == "t_123"
      assert run.trace_context.span_id == "s_456"
      assert run.trace_context.correlation_id == "c_789"
      assert run.trace_context.causation_id == "d_trace"
    end
  end

  defp unique_name(prefix) do
    String.to_atom("#{prefix}_#{System.unique_integer([:positive])}")
  end

  defp wait_for_dispatch(consumer, dispatch_id, predicate, timeout_ms \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_dispatch(consumer, dispatch_id, predicate, deadline)
  end

  defp do_wait_for_dispatch(consumer, dispatch_id, predicate, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      flunk("dispatch #{dispatch_id} did not reach expected state")
    end

    case Consumer.get_dispatch(consumer, dispatch_id) do
      {:ok, dispatch} ->
        if predicate.(dispatch) do
          dispatch
        else
          Process.sleep(10)
          do_wait_for_dispatch(consumer, dispatch_id, predicate, deadline)
        end

      {:error, :not_found} ->
        Process.sleep(10)
        do_wait_for_dispatch(consumer, dispatch_id, predicate, deadline)
    end
  end
end
