defmodule Jido.Integration.V2.DispatchRuntime do
  @moduledoc """
  Async trigger dispatch runtime with durable transport-state recovery.
  """

  use GenServer

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.DispatchRuntime.Dispatch
  alias Jido.Integration.V2.DispatchRuntime.Telemetry
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  @default_storage_dir Path.join(System.tmp_dir!(), "jido_integration_v2_dispatch_runtime")
  @state_file "dispatch_state.bin"

  @type execute_result ::
          {:ok, %{run: Run.t(), attempt: map(), output: map()}}
          | {:error,
             %{
               reason: term(),
               run: Run.t(),
               attempt: map() | nil,
               policy_decision: map() | nil
             }}
          | {:error, term()}

  @type runtime_state :: %{
          storage_path: String.t(),
          task_supervisor: pid(),
          dispatches: %{optional(String.t()) => Dispatch.t()},
          handlers: %{optional(String.t()) => module()},
          timers: %{optional(String.t()) => reference()},
          tasks: %{optional(String.t()) => pid()},
          max_attempts: pos_integer(),
          backoff_base_ms: pos_integer(),
          backoff_cap_ms: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(
      __MODULE__,
      opts,
      if(name, do: [name: name], else: [])
    )
  end

  @spec register_handler(GenServer.server(), String.t(), module()) :: :ok | {:error, term()}
  def register_handler(server, trigger_id, handler_module) do
    GenServer.call(server, {:register_handler, trigger_id, handler_module})
  end

  @spec enqueue(GenServer.server(), TriggerRecord.t(), keyword()) ::
          {:ok, %{status: :accepted | :duplicate, dispatch: Dispatch.t(), run: Run.t()}}
          | {:error, term()}
  def enqueue(server, %TriggerRecord{} = trigger, opts \\ []) do
    GenServer.call(server, {:enqueue, trigger, nil, opts}, :infinity)
  end

  @spec enqueue(GenServer.server(), TriggerRecord.t(), TriggerCheckpoint.t(), keyword()) ::
          {:ok, %{status: :accepted | :duplicate, dispatch: Dispatch.t(), run: Run.t()}}
          | {:error, term()}
  def enqueue(server, %TriggerRecord{} = trigger, %TriggerCheckpoint{} = checkpoint, opts) do
    GenServer.call(server, {:enqueue, trigger, checkpoint, opts}, :infinity)
  end

  @spec fetch_dispatch(GenServer.server(), String.t()) :: {:ok, Dispatch.t()} | :error
  def fetch_dispatch(server, dispatch_id) do
    GenServer.call(server, {:fetch_dispatch, dispatch_id})
  end

  @spec list_dispatches(GenServer.server(), keyword()) :: [Dispatch.t()]
  def list_dispatches(server, opts \\ []) do
    GenServer.call(server, {:list_dispatches, opts})
  end

  @spec replay(GenServer.server(), String.t()) :: {:ok, Dispatch.t()} | {:error, term()}
  def replay(server, dispatch_id) do
    GenServer.call(server, {:replay, dispatch_id}, :infinity)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    storage_path = storage_path(opts)
    File.mkdir_p!(Path.dirname(storage_path))
    {:ok, task_supervisor} = Task.Supervisor.start_link()

    dispatches =
      storage_path
      |> load_dispatches()
      |> recover_inflight_dispatches()

    state = %{
      storage_path: storage_path,
      task_supervisor: task_supervisor,
      dispatches: dispatches,
      handlers: %{},
      timers: %{},
      tasks: %{},
      max_attempts: Keyword.get(opts, :max_attempts, 5),
      backoff_base_ms: Keyword.get(opts, :backoff_base_ms, 1_000),
      backoff_cap_ms: Keyword.get(opts, :backoff_cap_ms, 30_000)
    }

    {:ok, persist_dispatches(state)}
  end

  @impl true
  def handle_call({:register_handler, trigger_id, handler_module}, _from, state) do
    if valid_handler_module?(handler_module) do
      state =
        state
        |> put_in([:handlers, trigger_id], handler_module)
        |> schedule_dispatches_for_trigger(trigger_id)

      {:reply, :ok, state}
    else
      {:reply, {:error, :invalid_handler_module}, state}
    end
  end

  def handle_call({:enqueue, trigger, checkpoint, opts}, _from, state) do
    dispatch_id = dispatch_id(trigger)

    case Map.get(state.dispatches, dispatch_id) do
      nil ->
        dispatch =
          Dispatch.new!(%{
            dispatch_id: dispatch_id,
            trigger: trigger,
            checkpoint: checkpoint,
            status: :queued,
            run_id: trigger.run_id,
            max_attempts: Keyword.get(opts, :max_attempts, state.max_attempts),
            attempts: 0
          })

        state = put_dispatch(state, dispatch)

        case ensure_run_bound(dispatch) do
          {:ok, status, bound_dispatch, run} ->
            Telemetry.emit(
              :enqueue,
              %{count: 1},
              dispatch_metadata(bound_dispatch, %{status: status})
            )

            state =
              state
              |> put_dispatch(bound_dispatch)
              |> maybe_schedule_dispatch(bound_dispatch)

            {:reply, {:ok, %{status: status, dispatch: bound_dispatch, run: run}}, state}

          {:error, reason, failed_dispatch} ->
            {:reply, {:error, reason}, put_dispatch(state, failed_dispatch)}
        end

      %Dispatch{} = existing_dispatch ->
        case ensure_run_bound(existing_dispatch) do
          {:ok, _status, bound_dispatch, run} ->
            Telemetry.emit(
              :enqueue,
              %{count: 1},
              dispatch_metadata(bound_dispatch, %{status: :duplicate})
            )

            state =
              state
              |> put_dispatch(bound_dispatch)
              |> maybe_schedule_dispatch(bound_dispatch)

            {:reply, {:ok, %{status: :duplicate, dispatch: bound_dispatch, run: run}}, state}

          {:error, reason, failed_dispatch} ->
            {:reply, {:error, reason}, put_dispatch(state, failed_dispatch)}
        end
    end
  end

  def handle_call({:fetch_dispatch, dispatch_id}, _from, state) do
    reply =
      case Map.get(state.dispatches, dispatch_id) do
        %Dispatch{} = dispatch -> {:ok, dispatch}
        nil -> :error
      end

    {:reply, reply, state}
  end

  def handle_call({:list_dispatches, opts}, _from, state) do
    {:reply, filter_dispatches(state.dispatches, opts), state}
  end

  def handle_call({:replay, dispatch_id}, _from, state) do
    case Map.get(state.dispatches, dispatch_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %Dispatch{status: :dead_lettered} = dispatch ->
        replayed_dispatch = %{
          dispatch
          | status: :queued,
            available_at: Contracts.now(),
            last_error: nil,
            dead_lettered_at: nil,
            completed_at: nil,
            updated_at: Contracts.now()
        }

        state =
          state
          |> put_dispatch(replayed_dispatch)
          |> maybe_schedule_dispatch(replayed_dispatch)

        Telemetry.emit(
          :replay,
          %{attempts: dispatch.attempts},
          dispatch_metadata(replayed_dispatch)
        )

        {:reply, {:ok, replayed_dispatch}, state}

      %Dispatch{status: status} ->
        {:reply, {:error, {:invalid_status, status}}, state}
    end
  end

  @impl true
  def handle_info({:run_dispatch, dispatch_id}, state) do
    state =
      state
      |> clear_timer(dispatch_id)
      |> run_dispatch(dispatch_id)

    {:noreply, state}
  end

  def handle_info({:dispatch_result, dispatch_id, attempt_number, {:ok, %{run: run}}}, state) do
    state = pop_task(state, dispatch_id)

    case Map.get(state.dispatches, dispatch_id) do
      %Dispatch{status: :running, attempts: ^attempt_number} = dispatch ->
        completed_dispatch = %{
          dispatch
          | status: :completed,
            run_id: run.run_id,
            available_at: nil,
            last_error: nil,
            completed_at: Contracts.now(),
            updated_at: Contracts.now()
        }

        Telemetry.emit(
          :deliver,
          %{attempt: attempt_number},
          dispatch_metadata(completed_dispatch)
        )

        {:noreply, put_dispatch(state, completed_dispatch)}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:dispatch_result, dispatch_id, attempt_number, {:error, error}}, state) do
    state = pop_task(state, dispatch_id)

    case Map.get(state.dispatches, dispatch_id) do
      %Dispatch{status: :running, attempts: ^attempt_number} = dispatch ->
        {:noreply, handle_dispatch_failure(state, dispatch, error)}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, task_supervisor, reason}, %{task_supervisor: task_supervisor} = state) do
    {:stop, reason, state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.timers, fn {_dispatch_id, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)

    if is_pid(state.task_supervisor) and Process.alive?(state.task_supervisor) do
      Process.exit(state.task_supervisor, :shutdown)
    end

    :ok
  end

  defp start_dispatch_task(state, %Dispatch{} = dispatch) do
    parent = self()
    handler_module = Map.fetch!(state.handlers, dispatch.trigger.trigger_id)
    attempt_number = dispatch.attempts

    {:ok, task_pid} =
      Task.Supervisor.start_child(state.task_supervisor, fn ->
        result = execute_dispatch(handler_module, dispatch)
        send(parent, {:dispatch_result, dispatch.dispatch_id, attempt_number, result})
      end)

    put_in(state, [:tasks, dispatch.dispatch_id], task_pid)
  end

  defp execute_dispatch(handler_module, %Dispatch{} = dispatch) do
    context = %{
      dispatch: dispatch,
      attempt: dispatch.attempts,
      run_id: dispatch.run_id
    }

    case handler_module.execution_opts(dispatch.trigger, context) do
      {:ok, execution_opts} ->
        ControlPlane.execute_run(dispatch.run_id, dispatch.attempts, execution_opts)

      {:error, reason} ->
        dispatch_execution_error(dispatch, reason)

      other ->
        dispatch_execution_error(dispatch, {:invalid_execution_opts, other})
    end
  rescue
    exception ->
      dispatch_execution_error(dispatch, %{exception: Exception.message(exception), kind: :error})
  catch
    kind, reason ->
      dispatch_execution_error(dispatch, %{kind: kind, exception: inspect(reason)})
  end

  defp run_dispatch(state, dispatch_id) do
    case Map.get(state.dispatches, dispatch_id) do
      %Dispatch{} = dispatch -> maybe_run_dispatch(state, dispatch)
      nil -> state
    end
  end

  defp maybe_run_dispatch(state, %Dispatch{} = dispatch) do
    dispatch_id = dispatch.dispatch_id

    cond do
      dispatch.status not in [:queued, :retry_scheduled] ->
        state

      Map.has_key?(state.tasks, dispatch_id) ->
        state

      not handler_registered?(state, dispatch.trigger.trigger_id) ->
        state

      not due?(dispatch.available_at) ->
        maybe_schedule_dispatch(state, dispatch)

      true ->
        start_dispatch(state, dispatch)
    end
  end

  defp start_dispatch(state, %Dispatch{} = dispatch) do
    case ensure_run_bound(dispatch) do
      {:ok, _status, bound_dispatch, _run} ->
        running_dispatch = running_dispatch(bound_dispatch)

        state
        |> put_dispatch(running_dispatch)
        |> start_dispatch_task(running_dispatch)

      {:error, _reason, failed_dispatch} ->
        put_dispatch(state, failed_dispatch)
    end
  end

  defp running_dispatch(%Dispatch{} = dispatch) do
    %{
      dispatch
      | status: :running,
        attempts: dispatch.attempts + 1,
        available_at: nil,
        updated_at: Contracts.now()
    }
  end

  defp dispatch_execution_error(%Dispatch{} = dispatch, reason) do
    {:error,
     %{reason: reason, run: fetch_run!(dispatch.run_id), attempt: nil, policy_decision: nil}}
  end

  defp handle_dispatch_failure(state, %Dispatch{} = dispatch, error) do
    error_reason = error_reason(error)

    if terminal_error?(error_reason) or dispatch.attempts >= dispatch.max_attempts do
      dead_lettered_dispatch = %{
        dispatch
        | status: :dead_lettered,
          available_at: nil,
          dead_lettered_at: Contracts.now(),
          last_error: error_snapshot(error_reason, :execution),
          updated_at: Contracts.now()
      }

      Telemetry.emit(
        :dead_letter,
        %{attempts: dispatch.attempts},
        dispatch_metadata(dead_lettered_dispatch)
      )

      put_dispatch(state, dead_lettered_dispatch)
    else
      delay_ms = backoff_delay(dispatch.attempts, state.backoff_base_ms, state.backoff_cap_ms)

      retry_dispatch = %{
        dispatch
        | status: :retry_scheduled,
          available_at: DateTime.add(Contracts.now(), delay_ms, :millisecond),
          last_error: error_snapshot(error_reason, :execution),
          updated_at: Contracts.now()
      }

      Telemetry.emit(
        :retry,
        %{attempt: dispatch.attempts, backoff_ms: delay_ms},
        dispatch_metadata(retry_dispatch)
      )

      state
      |> put_dispatch(retry_dispatch)
      |> maybe_schedule_dispatch(retry_dispatch)
    end
  end

  defp ensure_run_bound(%Dispatch{run_id: run_id} = dispatch) when is_binary(run_id) do
    case ControlPlane.fetch_run(run_id) do
      {:ok, %Run{} = run} ->
        bound_dispatch = %{
          dispatch
          | trigger: %{dispatch.trigger | run_id: run_id},
            run_id: run_id,
            checkpoint: dispatch.checkpoint,
            last_error: nil,
            updated_at: Contracts.now()
        }

        {:ok, :accepted, bound_dispatch, run}

      :error ->
        ensure_run_bound(%{
          dispatch
          | trigger: %{dispatch.trigger | run_id: nil},
            run_id: nil
        })
    end
  end

  defp ensure_run_bound(%Dispatch{} = dispatch) do
    opts =
      case dispatch.checkpoint do
        %TriggerCheckpoint{} = checkpoint -> [checkpoint: checkpoint]
        nil -> []
      end

    trigger = %{dispatch.trigger | run_id: nil}

    case ControlPlane.admit_trigger(trigger, opts) do
      {:ok, %{status: status, trigger: bound_trigger, run: %Run{} = run}} ->
        bound_dispatch = %{
          dispatch
          | trigger: bound_trigger,
            run_id: run.run_id,
            last_error: nil,
            updated_at: Contracts.now()
        }

        {:ok, status, bound_dispatch, run}

      {:error, reason} ->
        {:error, reason, record_error(dispatch, reason, :bind)}
    end
  end

  defp maybe_schedule_dispatch(state, %Dispatch{} = dispatch) do
    cond do
      dispatch.status not in [:queued, :retry_scheduled] ->
        state

      not handler_registered?(state, dispatch.trigger.trigger_id) ->
        state

      Map.has_key?(state.tasks, dispatch.dispatch_id) ->
        state

      Map.has_key?(state.timers, dispatch.dispatch_id) ->
        state

      true ->
        delay_ms = schedule_delay_ms(dispatch.available_at)
        timer_ref = Process.send_after(self(), {:run_dispatch, dispatch.dispatch_id}, delay_ms)
        put_in(state, [:timers, dispatch.dispatch_id], timer_ref)
    end
  end

  defp schedule_dispatches_for_trigger(state, trigger_id) do
    Enum.reduce(state.dispatches, state, fn {_dispatch_id, dispatch}, acc ->
      if dispatch.trigger.trigger_id == trigger_id do
        maybe_schedule_dispatch(acc, dispatch)
      else
        acc
      end
    end)
  end

  defp put_dispatch(state, %Dispatch{} = dispatch) do
    state
    |> put_in([:dispatches, dispatch.dispatch_id], dispatch)
    |> persist_dispatches()
  end

  defp persist_dispatches(%{storage_path: storage_path, dispatches: dispatches} = state) do
    tmp_path = "#{storage_path}.tmp"
    File.mkdir_p!(Path.dirname(storage_path))
    File.write!(tmp_path, :erlang.term_to_binary(dispatches), [:binary])

    case File.rename(tmp_path, storage_path) do
      :ok ->
        state

      {:error, _reason} ->
        File.rm(storage_path)
        File.rename!(tmp_path, storage_path)
        state
    end
  end

  defp pop_task(state, dispatch_id) do
    update_in(state, [:tasks], &Map.delete(&1, dispatch_id))
  end

  defp clear_timer(state, dispatch_id) do
    case Map.pop(state.timers, dispatch_id) do
      {nil, _timers} ->
        state

      {timer_ref, timers} ->
        Process.cancel_timer(timer_ref)
        %{state | timers: timers}
    end
  end

  defp fetch_run!(run_id) do
    case ControlPlane.fetch_run(run_id) do
      {:ok, %Run{} = run} -> run
      :error -> raise KeyError, key: run_id, term: :run
    end
  end

  defp filter_dispatches(dispatches, opts) do
    dispatches
    |> Map.values()
    |> Enum.filter(fn dispatch ->
      matches_status?(dispatch.status, Keyword.get(opts, :status), Keyword.get(opts, :statuses)) and
        matches_value?(dispatch.trigger.connector_id, Keyword.get(opts, :connector_id)) and
        matches_value?(dispatch.trigger.trigger_id, Keyword.get(opts, :trigger_id)) and
        matches_value?(dispatch.run_id, Keyword.get(opts, :run_id)) and
        matches_value?(dispatch.dispatch_id, Keyword.get(opts, :dispatch_id))
    end)
    |> Enum.sort_by(fn dispatch ->
      {DateTime.to_unix(dispatch.inserted_at, :microsecond), dispatch.dispatch_id}
    end)
  end

  defp matches_status?(_value, nil, nil), do: true
  defp matches_status?(value, expected, nil), do: value == expected
  defp matches_status?(value, nil, expected_values), do: value in expected_values

  defp matches_status?(value, expected, expected_values),
    do: value == expected and value in expected_values

  defp matches_value?(_value, nil), do: true
  defp matches_value?(value, expected), do: value == expected

  defp due?(nil), do: true

  defp due?(%DateTime{} = available_at),
    do: DateTime.compare(available_at, Contracts.now()) != :gt

  defp schedule_delay_ms(nil), do: 0

  defp schedule_delay_ms(%DateTime{} = available_at) do
    available_at
    |> DateTime.diff(Contracts.now(), :millisecond)
    |> max(0)
  end

  defp error_reason(%{reason: reason}), do: reason
  defp error_reason(reason), do: reason

  defp error_snapshot(reason, stage) do
    %{
      stage: stage,
      reason: inspect(reason),
      recorded_at: Contracts.now()
    }
  end

  defp record_error(%Dispatch{} = dispatch, reason, stage) do
    %{
      dispatch
      | last_error: error_snapshot(reason, stage),
        updated_at: Contracts.now()
    }
  end

  defp terminal_error?(:policy_denied), do: true
  defp terminal_error?(:policy_shed), do: true
  defp terminal_error?(:run_completed), do: true
  defp terminal_error?(:run_denied), do: true
  defp terminal_error?(:run_shed), do: true
  defp terminal_error?(_reason), do: false

  defp backoff_delay(attempts, base_ms, cap_ms) do
    multiplier = Integer.pow(2, max(attempts - 1, 0))
    min(base_ms * multiplier, cap_ms)
  end

  defp handler_registered?(state, trigger_id), do: Map.has_key?(state.handlers, trigger_id)

  defp valid_handler_module?(handler_module) do
    Code.ensure_loaded?(handler_module) and function_exported?(handler_module, :execution_opts, 2)
  end

  defp recover_inflight_dispatches(dispatches) do
    now = Contracts.now()

    Enum.into(dispatches, %{}, fn {dispatch_id, dispatch} ->
      next_dispatch =
        case dispatch.status do
          :running ->
            %{
              dispatch
              | status: :queued,
                available_at: now,
                last_error: error_snapshot(:runtime_restarted, :recovery),
                updated_at: now
            }

          _other ->
            dispatch
        end

      {dispatch_id, next_dispatch}
    end)
  end

  defp dispatch_id(%TriggerRecord{} = trigger) do
    hash_input =
      [
        trigger.tenant_id,
        trigger.connector_id,
        trigger.trigger_id,
        trigger.dedupe_key
      ]
      |> Enum.join("|")

    "dispatch-" <> Base.encode16(:crypto.hash(:sha256, hash_input), case: :lower)
  end

  defp dispatch_metadata(%Dispatch{} = dispatch, extra \\ %{}) do
    %{
      dispatch_id: dispatch.dispatch_id,
      run_id: dispatch.run_id,
      status: dispatch.status,
      attempts: dispatch.attempts,
      max_attempts: dispatch.max_attempts,
      dispatch_status: dispatch.status,
      trigger: trigger_metadata(dispatch.trigger),
      last_error: dispatch.last_error
    }
    |> maybe_put(:available_at, dispatch.available_at)
    |> maybe_put(:completed_at, dispatch.completed_at)
    |> maybe_put(:dead_lettered_at, dispatch.dead_lettered_at)
    |> Map.merge(extra)
  end

  defp trigger_metadata(%TriggerRecord{} = trigger) do
    %{
      admission_id: trigger.admission_id,
      source: trigger.source,
      connector_id: trigger.connector_id,
      trigger_id: trigger.trigger_id,
      capability_id: trigger.capability_id,
      tenant_id: trigger.tenant_id,
      external_id: trigger.external_id,
      dedupe_key: trigger.dedupe_key,
      status: trigger.status,
      run_id: trigger.run_id,
      payload: trigger.payload,
      signal: trigger.signal
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp storage_path(opts) do
    opts
    |> Keyword.get(:storage_dir, @default_storage_dir)
    |> Path.expand()
    |> Path.join(@state_file)
  end

  defp load_dispatches(path) do
    case File.read(path) do
      {:ok, binary} ->
        :erlang.binary_to_term(binary, [:safe])

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        raise "unable to load dispatch runtime state from #{path}: #{inspect(reason)}"
    end
  end
end
