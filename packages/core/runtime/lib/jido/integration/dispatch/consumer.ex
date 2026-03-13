defmodule Jido.Integration.Dispatch.Consumer do
  @moduledoc """
  Durable Build-Now dispatch consumer.

  Dispatch acceptance writes a durable dispatch record first, persists a durable
  run record at the acknowledgement point, then executes the callback
  asynchronously. Accepted, running, failed, and queued records are recovered on
  restart once a callback is registered for the trigger.

  Transport telemetry is emitted under `jido.integration.dispatch.*`.
  Execution telemetry is emitted separately under `jido.integration.run.*`.
  Legacy `jido.integration.dispatch_stub.*` events remain as temporary
  compatibility aliases during migration.

  `Dispatch.Consumer` is shipped by the runtime package, but it is currently a
  host-owned runtime role. The root `:jido_integration` application does not
  auto-start a default consumer.

  Hosts supervise this process so they can choose:

  - consumer naming and topology
  - dispatch and run store adapters
  - retry and backoff settings
  - callback registration strategy

  The consumer also exposes query APIs for durable transport and execution
  state:

  - `get_dispatch/2`
  - `list_dispatches/2`
  - `get_run/2`
  - `list_runs/2`

  Pre-ack store failures return explicit errors instead of returning success or
  crashing the consumer.
  """

  use GenServer

  alias Jido.Integration.{Dispatch, Error, Telemetry}
  alias Jido.Integration.Dispatch.{Record, Run, RunStore, Store}

  @type status :: Run.status()
  @type run :: Run.t()

  @default_max_attempts 5
  @default_backoff_base_ms 1_000
  @default_backoff_cap_ms 30_000

  @doc """
  Start a dispatch consumer under host supervision.

  Hosts typically configure storage, retry policy, and process naming here, then
  register callback modules before handing the consumer to webhook ingress.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register the callback module that should handle a trigger ID on this consumer.
  """
  @spec register_callback(GenServer.server(), String.t(), module()) :: :ok | {:error, term()}
  def register_callback(server, trigger_id, callback_module) do
    GenServer.call(server, {:register_callback, trigger_id, callback_module})
  end

  @doc """
  Accept a normalized dispatch record into the durable dispatch pipeline.
  """
  @spec dispatch(GenServer.server(), map()) ::
          {:ok, String.t()} | {:duplicate, String.t()} | {:error, term()}
  def dispatch(server, dispatch_record) when is_map(dispatch_record) do
    GenServer.call(server, {:dispatch, dispatch_record})
  end

  @doc """
  Fetch a durable dispatch record by `dispatch_id`.
  """
  @spec get_dispatch(GenServer.server(), String.t()) ::
          {:ok, Record.t()} | {:error, :not_found}
  def get_dispatch(server, dispatch_id) do
    GenServer.call(server, {:get_dispatch, dispatch_id})
  end

  @spec get_run(GenServer.server(), String.t()) :: {:ok, run()} | {:error, :not_found}
  @doc """
  Fetch a durable execution run by `run_id`.
  """
  def get_run(server, run_id) do
    GenServer.call(server, {:get_run, run_id})
  end

  @doc """
  List durable dispatch records, optionally filtered by status and scope fields.
  """
  @spec list_dispatches(GenServer.server(), keyword()) :: [Record.t()]
  def list_dispatches(server, opts \\ []) do
    GenServer.call(server, {:list_dispatches, opts})
  end

  @doc """
  List durable runs, optionally filtered by status and scope fields.
  """
  @spec list_runs(GenServer.server(), keyword()) :: [run()]
  def list_runs(server, opts \\ []) do
    GenServer.call(server, {:list_runs, opts})
  end

  @doc """
  Replay a dead-lettered run on a new attempt.
  """
  @spec replay(GenServer.server(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def replay(server, run_id) do
    GenServer.call(server, {:replay, run_id})
  end

  @impl GenServer
  def init(opts) do
    dispatch_store_module = Keyword.get(opts, :dispatch_store_module, Store.Disk)
    run_store_module = Keyword.get(opts, :run_store_module, RunStore.Disk)

    {:ok, dispatch_store} =
      dispatch_store_module.start_link(
        Keyword.put_new(store_opts(opts, :dispatch_store_opts), :name, nil)
      )

    {:ok, run_store} =
      run_store_module.start_link(Keyword.put_new(store_opts(opts, :run_store_opts), :name, nil))

    state = %{
      callbacks: %{},
      tasks: %{},
      idempotency_index: load_idempotency_index(run_store_module, run_store),
      dispatch_store_module: dispatch_store_module,
      dispatch_store: dispatch_store,
      run_store_module: run_store_module,
      run_store: run_store,
      max_attempts: Keyword.get(opts, :max_attempts, @default_max_attempts),
      backoff_base_ms: Keyword.get(opts, :backoff_base_ms, @default_backoff_base_ms),
      backoff_cap_ms: Keyword.get(opts, :backoff_cap_ms, @default_backoff_cap_ms)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register_callback, trigger_id, callback_module}, _from, state) do
    case valid_callback_module?(callback_module) do
      true ->
        state =
          state
          |> put_in([:callbacks, trigger_id], callback_module)
          |> recover_trigger(trigger_id)

        {:reply, :ok, state}

      false ->
        {:reply, {:error, :invalid_callback_module}, state}
    end
  end

  @impl GenServer
  def handle_call({:dispatch, record}, _from, state) do
    with :ok <- validate_dispatch_record(record),
         trigger_id <- Map.fetch!(record, :trigger_id),
         {:ok, _callback_module} <- fetch_callback_module(state, trigger_id) do
      idempotency_key = Map.get(record, :idempotency_key) || Map.fetch!(record, :dispatch_id)

      case lookup_existing_run(state, idempotency_key) do
        {:ok, existing_run_id, state} ->
          {:reply, {:duplicate, existing_run_id}, state}

        {:error, :not_found, state} ->
          dispatch_record = build_dispatch_record(record, idempotency_key, state)

          case state.dispatch_store_module.put(state.dispatch_store, dispatch_record) do
            :ok ->
              emit_dispatch_telemetry("jido.integration.dispatch.enqueued", dispatch_record)
              {reply, state} = accept_dispatch(dispatch_record, state)
              {:reply, reply, state}

            {:error, reason} ->
              {:reply, {:error, {:dispatch_store_put_failed, reason}}, state}
          end
      end
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_dispatch, dispatch_id}, _from, state) do
    {:reply, state.dispatch_store_module.fetch(state.dispatch_store, dispatch_id), state}
  end

  @impl GenServer
  def handle_call({:get_run, run_id}, _from, state) do
    {:reply, state.run_store_module.fetch(state.run_store, run_id), state}
  end

  @impl GenServer
  def handle_call({:list_dispatches, opts}, _from, state) do
    {:reply, state.dispatch_store_module.list(state.dispatch_store, opts), state}
  end

  @impl GenServer
  def handle_call({:list_runs, opts}, _from, state) do
    {:reply, state.run_store_module.list(state.run_store, opts), state}
  end

  @impl GenServer
  def handle_call({:replay, run_id}, _from, state) do
    case state.run_store_module.fetch(state.run_store, run_id) do
      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}

      {:ok, %Run{status: :dead_lettered} = run} ->
        replayed = %{
          run
          | status: :accepted,
            attempt: run.attempt + 1,
            attempt_id: attempt_id(run.run_id, run.attempt + 1),
            result: nil,
            error_class: nil,
            error_context: nil,
            accepted_at: DateTime.utc_now(),
            started_at: nil,
            finished_at: nil,
            updated_at: DateTime.utc_now()
        }

        :ok = state.run_store_module.put(state.run_store, replayed)
        restore_dispatch_delivery_state(replayed, state)
        emit_dispatch_telemetry("jido.integration.dispatch.replayed", replayed)
        emit_run_telemetry("jido.integration.run.accepted", replayed)
        emit_legacy_run_alias("jido.integration.dispatch_stub.accepted", replayed)
        schedule_execute(run_id, 0)
        {:reply, {:ok, run_id}, state}

      {:ok, %Run{status: status}} ->
        {:reply, {:error, {:invalid_status, status}}, state}
    end
  end

  @impl GenServer
  def handle_info({:execute, run_id}, state) do
    cond do
      Map.has_key?(state.tasks, run_id) ->
        {:noreply, state}

      true ->
        case state.run_store_module.fetch(state.run_store, run_id) do
          {:ok, %Run{status: status}} when status in [:succeeded, :dead_lettered] ->
            {:noreply, state}

          {:ok, %Run{} = run} ->
            {:noreply, execute_run(run, state)}

          {:error, :not_found} ->
            {:noreply, state}
        end
    end
  end

  @impl GenServer
  def handle_info({:execution_result, run_id, attempt_id, {:ok, result}}, state) do
    case state.run_store_module.fetch(state.run_store, run_id) do
      {:ok, %Run{status: :running, attempt_id: ^attempt_id} = run} ->
        finished_at = DateTime.utc_now()

        run = %{
          run
          | status: :succeeded,
            result: result,
            error_class: nil,
            error_context: nil,
            finished_at: finished_at,
            updated_at: finished_at
        }

        :ok = state.run_store_module.put(state.run_store, run)
        restore_dispatch_delivery_state(run, state)
        emit_run_telemetry("jido.integration.run.succeeded", run)
        emit_legacy_run_alias("jido.integration.dispatch_stub.succeeded", run)

        {:noreply, update_in(state.tasks, &Map.delete(&1, run_id))}

      _ ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:execution_result, run_id, attempt_id, {:error, reason}}, state) do
    case state.run_store_module.fetch(state.run_store, run_id) do
      {:ok, %Run{status: :running, attempt_id: ^attempt_id} = run} ->
        state =
          state
          |> update_in([:tasks], &Map.delete(&1, run_id))
          |> handle_failure(run, reason)

        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  defp accept_dispatch(%Record{} = record, state) do
    case lookup_existing_run(state, record.idempotency_key) do
      {:ok, existing_run_id, state} ->
        updated_record = delivered_record(record, existing_run_id)

        case state.dispatch_store_module.put(state.dispatch_store, updated_record) do
          :ok ->
            emit_dispatch_telemetry("jido.integration.dispatch.delivered", updated_record)
            {{:duplicate, existing_run_id}, state}

          {:error, reason} ->
            {{:error, {:dispatch_store_put_failed, reason}}, state}
        end

      {:error, :not_found, state} ->
        callback_module = Map.fetch!(state.callbacks, record.trigger_id)
        run = new_run(record, callback_module, state.max_attempts)

        case state.run_store_module.put(state.run_store, run) do
          :ok ->
            updated_record = delivered_record(record, run.run_id)

            case state.dispatch_store_module.put(state.dispatch_store, updated_record) do
              :ok ->
                emit_dispatch_telemetry(
                  "jido.integration.dispatch.delivered",
                  updated_record,
                  run
                )

                emit_run_telemetry("jido.integration.run.accepted", run)
                emit_legacy_run_alias("jido.integration.dispatch_stub.accepted", run)
                schedule_execute(run.run_id, 0)

                {{:ok, run.run_id},
                 %{
                   state
                   | idempotency_index:
                       Map.put(state.idempotency_index, run.idempotency_key, run.run_id)
                 }}

              {:error, reason} ->
                _ = state.run_store_module.delete(state.run_store, run.run_id)
                {{:error, {:dispatch_store_put_failed, reason}}, state}
            end

          {:error, {:idempotency_conflict, existing_run_id}} ->
            updated_record = delivered_record(record, existing_run_id)

            case state.dispatch_store_module.put(state.dispatch_store, updated_record) do
              :ok ->
                emit_dispatch_telemetry("jido.integration.dispatch.delivered", updated_record)

                {{:duplicate, existing_run_id},
                 %{
                   state
                   | idempotency_index:
                       Map.put(state.idempotency_index, record.idempotency_key, existing_run_id)
                 }}

              {:error, reason} ->
                {{:error, {:dispatch_store_put_failed, reason}}, state}
            end

          {:error, reason} ->
            {{:error, {:run_store_put_failed, reason}}, state}
        end
    end
  end

  defp recover_trigger(state, trigger_id) do
    state =
      state.dispatch_store_module.list(state.dispatch_store,
        trigger_id: trigger_id,
        status: :queued
      )
      |> Enum.reduce(state, fn record, acc ->
        {_reply, acc} = accept_dispatch(record, acc)
        acc
      end)

    state.run_store_module.list(state.run_store,
      trigger_id: trigger_id,
      statuses: [:accepted, :running, :failed]
    )
    |> Enum.reduce(state, fn run, acc ->
      schedule_execute(run.run_id, 0)
      acc
    end)
  end

  defp execute_run(%Run{} = run, state) do
    attempt =
      case run.status do
        :failed -> run.attempt + 1
        _ -> run.attempt
      end

    started_at = DateTime.utc_now()

    run = %{
      run
      | status: :running,
        attempt: attempt,
        attempt_id: attempt_id(run.run_id, attempt),
        started_at: started_at,
        finished_at: nil,
        error_class: nil,
        error_context: nil,
        updated_at: started_at
    }

    :ok = state.run_store_module.put(state.run_store, run)

    callback_module = Map.fetch!(state.callbacks, run.trigger_id)
    task = start_execution_task(self(), run, callback_module)
    emit_run_telemetry("jido.integration.run.started", run)
    emit_legacy_run_alias("jido.integration.dispatch_stub.started", run)

    put_in(state.tasks[run.run_id], task)
  end

  defp start_execution_task(server, run, callback_module) do
    {:ok, task} =
      Task.start(fn ->
        result = invoke_callback(callback_module, run)
        send(server, {:execution_result, run.run_id, run.attempt_id, result})
      end)

    task
  end

  defp invoke_callback(callback_module, run) do
    event = run.payload

    context = %{
      run_id: run.run_id,
      attempt: run.attempt,
      attempt_id: run.attempt_id,
      dispatch_id: run.dispatch_id,
      idempotency_key: run.idempotency_key,
      tenant_id: run.tenant_id,
      connector_id: run.connector_id,
      trigger_id: run.trigger_id,
      callback_id: run.callback_id,
      trace_context: run.trace_context
    }

    case callback_module.handle_trigger(event, context) do
      :ok -> {:ok, %{}}
      {:ok, result} when is_map(result) -> {:ok, result}
      {:error, reason} -> {:error, reason}
      other -> {:error, %{error: "invalid_callback_response", response: inspect(other)}}
    end
  rescue
    exception ->
      {:error,
       %{
         exception: Exception.message(exception),
         kind: "error",
         stacktrace: Exception.format(:error, exception, __STACKTRACE__)
       }}
  catch
    kind, reason ->
      {:error, %{exception: inspect(reason), kind: to_string(kind)}}
  end

  defp handle_failure(state, %Run{} = run, reason) do
    {error_class, error_context} = normalize_error(reason)
    finished_at = DateTime.utc_now()

    failed_run = %{
      run
      | status: :failed,
        error_class: error_class,
        error_context: error_context,
        finished_at: finished_at,
        updated_at: finished_at
    }

    :ok = state.run_store_module.put(state.run_store, failed_run)
    emit_run_telemetry("jido.integration.run.failed", failed_run)
    emit_legacy_run_alias("jido.integration.dispatch_stub.failed", failed_run)

    if failed_run.attempt >= failed_run.max_attempts do
      dead_lettered = %{failed_run | status: :dead_lettered, updated_at: DateTime.utc_now()}
      :ok = state.run_store_module.put(state.run_store, dead_lettered)
      mark_dispatch_dead_lettered(dead_lettered, state)
      emit_run_telemetry("jido.integration.run.dead_lettered", dead_lettered)
      emit_dispatch_telemetry("jido.integration.dispatch.dead_lettered", dead_lettered)
      emit_legacy_run_alias("jido.integration.dispatch_stub.dead_lettered", dead_lettered)
      state
    else
      delay = backoff_delay(failed_run.attempt, state.backoff_base_ms, state.backoff_cap_ms)
      schedule_execute(failed_run.run_id, delay)
      state
    end
  end

  defp mark_dispatch_dead_lettered(%Run{} = run, state) do
    case state.dispatch_store_module.fetch(state.dispatch_store, run.dispatch_id) do
      {:ok, %Record{} = record} ->
        updated = %{
          record
          | status: :dead_lettered,
            error_context: run.error_context,
            updated_at: DateTime.utc_now()
        }

        :ok = state.dispatch_store_module.put(state.dispatch_store, updated)

      {:error, :not_found} ->
        :ok
    end
  end

  defp restore_dispatch_delivery_state(%Run{} = run, state) do
    case state.dispatch_store_module.fetch(state.dispatch_store, run.dispatch_id) do
      {:ok, %Record{} = record} ->
        updated = %{
          record
          | status: :delivered,
            run_id: run.run_id,
            error_context: nil,
            updated_at: DateTime.utc_now()
        }

        :ok = state.dispatch_store_module.put(state.dispatch_store, updated)

      {:error, :not_found} ->
        :ok
    end
  end

  defp build_dispatch_record(record, idempotency_key, state) do
    max_attempts =
      Map.get(record, :max_dispatch_attempts, Map.get(record, :max_attempts, state.max_attempts))

    Dispatch.Record.new(%{
      dispatch_id: Map.fetch!(record, :dispatch_id),
      idempotency_key: idempotency_key,
      tenant_id: Map.get(record, :tenant_id),
      connector_id: Map.get(record, :connector_id),
      trigger_id: Map.fetch!(record, :trigger_id),
      event_id: Map.get(record, :event_id),
      dedupe_key: Map.get(record, :dedupe_key),
      workflow_selector: Map.get(record, :workflow_selector, Map.fetch!(record, :trigger_id)),
      payload: Map.get(record, :payload, %{}),
      max_dispatch_attempts: max_attempts,
      trace_context: normalize_trace_context(Map.get(record, :trace_context, %{}), record)
    })
  end

  defp new_run(%Record{} = record, callback_module, _default_max_attempts) do
    run_id = generate_run_id()
    now = DateTime.utc_now()
    attempt = 1

    %Run{
      run_id: run_id,
      attempt_id: attempt_id(run_id, attempt),
      dispatch_id: record.dispatch_id,
      idempotency_key: record.idempotency_key,
      tenant_id: record.tenant_id,
      connector_id: record.connector_id,
      trigger_id: record.trigger_id,
      callback_id: callback_id(callback_module),
      status: :accepted,
      attempt: attempt,
      max_attempts: record.max_dispatch_attempts,
      payload: record.payload,
      trace_context: record.trace_context,
      accepted_at: now,
      started_at: nil,
      finished_at: nil,
      updated_at: now
    }
  end

  defp load_idempotency_index(run_store_module, run_store) do
    run_store_module.list(run_store)
    |> Enum.reduce(%{}, fn run, acc -> Map.put(acc, run.idempotency_key, run.run_id) end)
  end

  defp lookup_existing_run(state, idempotency_key) do
    case Map.get(state.idempotency_index, idempotency_key) do
      nil ->
        case state.run_store_module.fetch_by_idempotency(state.run_store, idempotency_key) do
          {:ok, %Run{run_id: run_id}} ->
            {:ok, run_id,
             %{
               state
               | idempotency_index: Map.put(state.idempotency_index, idempotency_key, run_id)
             }}

          {:error, :not_found} ->
            {:error, :not_found, state}
        end

      run_id ->
        {:ok, run_id, state}
    end
  end

  defp delivered_record(%Record{} = record, run_id) do
    %{
      record
      | status: :delivered,
        attempts: max(record.attempts, 1),
        run_id: run_id,
        updated_at: DateTime.utc_now()
    }
  end

  defp emit_dispatch_telemetry(event_name, %Record{} = record) do
    metadata = %{
      run_id: record.run_id,
      dispatch_id: record.dispatch_id,
      tenant_id: record.tenant_id,
      connector_id: record.connector_id,
      trigger_id: record.trigger_id,
      callback_id: nil,
      attempt: record.attempts,
      trace_id: record.trace_context[:trace_id],
      span_id: record.trace_context[:span_id],
      correlation_id: record.trace_context[:correlation_id]
    }

    Telemetry.emit(event_name, %{}, metadata)
  end

  defp emit_dispatch_telemetry(event_name, %Run{} = run) do
    metadata = %{
      run_id: run.run_id,
      dispatch_id: run.dispatch_id,
      tenant_id: run.tenant_id,
      connector_id: run.connector_id,
      trigger_id: run.trigger_id,
      callback_id: run.callback_id,
      attempt: run.attempt,
      trace_id: run.trace_context[:trace_id],
      span_id: run.trace_context[:span_id],
      correlation_id: run.trace_context[:correlation_id]
    }

    Telemetry.emit(event_name, %{}, metadata)
  end

  defp emit_dispatch_telemetry(event_name, %Record{} = record, %Run{} = run) do
    metadata = %{
      run_id: run.run_id,
      dispatch_id: record.dispatch_id,
      tenant_id: record.tenant_id,
      connector_id: record.connector_id,
      trigger_id: record.trigger_id,
      callback_id: run.callback_id,
      attempt: run.attempt,
      trace_id: record.trace_context[:trace_id],
      span_id: record.trace_context[:span_id],
      correlation_id: record.trace_context[:correlation_id]
    }

    Telemetry.emit(event_name, %{}, metadata)
  end

  defp emit_run_telemetry(event_name, %Run{} = run) do
    metadata = %{
      run_id: run.run_id,
      attempt_id: run.attempt_id,
      dispatch_id: run.dispatch_id,
      tenant_id: run.tenant_id,
      connector_id: run.connector_id,
      trigger_id: run.trigger_id,
      callback_id: run.callback_id,
      attempt: run.attempt,
      error_class: run.error_class,
      trace_id: run.trace_context[:trace_id],
      span_id: run.trace_context[:span_id],
      correlation_id: run.trace_context[:correlation_id],
      causation_id: run.trace_context[:causation_id]
    }

    Telemetry.emit(event_name, %{}, metadata)
  end

  defp emit_legacy_run_alias(event_name, %Run{} = run) do
    metadata = %{
      run_id: run.run_id,
      dispatch_id: run.dispatch_id,
      tenant_id: run.tenant_id,
      connector_id: run.connector_id,
      trigger_id: run.trigger_id,
      callback_id: run.callback_id,
      attempt: run.attempt,
      trace_id: run.trace_context[:trace_id],
      span_id: run.trace_context[:span_id],
      correlation_id: run.trace_context[:correlation_id]
    }

    Telemetry.emit(event_name, %{}, metadata)
  end

  defp validate_dispatch_record(record) do
    cond do
      missing_string?(Map.get(record, :dispatch_id)) ->
        {:error, :dispatch_id_required}

      missing_string?(Map.get(record, :trigger_id)) ->
        {:error, :trigger_id_required}

      Map.has_key?(record, :payload) and not is_map(Map.get(record, :payload)) ->
        {:error, :payload_must_be_map}

      Map.get(
        record,
        :max_dispatch_attempts,
        Map.get(record, :max_attempts, @default_max_attempts)
      ) <=
          0 ->
        {:error, :max_attempts_must_be_positive}

      true ->
        :ok
    end
  end

  defp fetch_callback_module(state, trigger_id) do
    case Map.get(state.callbacks, trigger_id) do
      nil -> {:error, :no_callback_registered}
      module -> {:ok, module}
    end
  end

  defp normalize_trace_context(trace_context, record) do
    %{
      trace_id: trace_context[:trace_id] || trace_context["trace_id"],
      span_id: trace_context[:span_id] || trace_context["span_id"],
      correlation_id: trace_context[:correlation_id] || trace_context["correlation_id"],
      causation_id:
        trace_context[:causation_id] || trace_context["causation_id"] ||
          Map.fetch!(record, :dispatch_id)
    }
  end

  defp normalize_error(%Error{} = error) do
    {to_string(error.class),
     %{
       "message" => error.message,
       "code" => error.code,
       "retryability" => to_string(error.retryability),
       "upstream_context" => error.upstream_context
     }}
  end

  defp normalize_error(reason) when is_map(reason) do
    error_class =
      reason[:error_class] || reason["error_class"] || reason[:class] || reason["class"]

    {error_class && to_string(error_class), Map.new(reason, fn {k, v} -> {to_string(k), v} end)}
  end

  defp normalize_error(reason) when is_binary(reason), do: {nil, %{"error" => reason}}

  defp normalize_error(reason) when is_atom(reason),
    do: {nil, %{"error" => Atom.to_string(reason)}}

  defp normalize_error(reason), do: {nil, %{"error" => inspect(reason)}}

  defp store_opts(opts, key), do: Keyword.get(opts, key, [])

  defp schedule_execute(run_id, delay_ms) do
    Process.send_after(self(), {:execute, run_id}, delay_ms)
  end

  defp backoff_delay(attempt, base_ms, cap_ms) do
    delay = (base_ms * :math.pow(2, attempt - 1)) |> trunc()
    min(delay, cap_ms)
  end

  defp callback_id(module), do: inspect(module)

  defp missing_string?(value), do: not is_binary(value) or value == ""

  defp valid_callback_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :handle_trigger, 2)
  end

  defp valid_callback_module?(_module), do: false

  defp attempt_id(run_id, attempt), do: "#{run_id}:#{attempt}"

  defp generate_run_id do
    <<a1::32, a2::16, a3::16, a4::16, a5::48>> = :crypto.strong_rand_bytes(16)
    version = Bitwise.bor(Bitwise.band(a3, 0x0FFF), 0x4000)
    variant = Bitwise.bor(Bitwise.band(a4, 0x3FFF), 0x8000)

    [
      Base.encode16(<<a1::32>>, case: :lower),
      Base.encode16(<<a2::16>>, case: :lower),
      Base.encode16(<<version::16>>, case: :lower),
      Base.encode16(<<variant::16>>, case: :lower),
      Base.encode16(<<a5::48>>, case: :lower)
    ]
    |> Enum.join("-")
  end
end
