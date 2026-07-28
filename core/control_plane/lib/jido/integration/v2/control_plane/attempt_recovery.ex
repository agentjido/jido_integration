defmodule Jido.Integration.V2.ControlPlane.AttemptRecovery do
  @moduledoc """
  Durable, observation-only reconciliation for provider attempts.

  A recovery task is created from an attempt that already owns a stable
  external operation reference. Reconciliation may observe, cancel, or clean
  that operation, but this module has no dispatch path and cannot replay an
  effect.
  """

  alias Jido.Integration.V2.{
    Attempt,
    Auth,
    Contracts,
    Event,
    RecoveryTask,
    Redaction
  }

  alias Jido.Integration.V2.Auth.SecretGuard
  alias Jido.Integration.V2.ControlPlane.Stores

  @default_claim_ttl_ms 30_000
  @default_retry_delay_ms 5_000
  @default_max_retries 5
  @default_limit 100
  @terminal_task_statuses [:resolved, :quarantined]
  @terminal_attempt_statuses [:completed, :failed]
  @protected_metadata_keys [
    :credential_lease_id,
    :deadline_at,
    :effect_retry,
    :external_operation_ref,
    "credential_lease_id",
    "deadline_at",
    "effect_retry",
    "external_operation_ref"
  ]

  @type summary :: %{
          discovered: non_neg_integer(),
          reconciled: non_neg_integer(),
          deferred: non_neg_integer(),
          operator_required: non_neg_integer()
        }

  @spec mark_outcome_unknown(String.t(), map() | keyword()) ::
          {:ok, RecoveryTask.t()} | {:error, term()}
  def mark_outcome_unknown(attempt_id, attrs \\ %{}) when is_binary(attempt_id) do
    case put_outcome_unknown(attempt_id, attrs) do
      {:ok, task, _disposition} -> {:ok, task}
      {:error, _reason} = error -> error
    end
  end

  defp put_outcome_unknown(attempt_id, attrs) do
    attrs = Map.new(attrs)

    with {:ok, %Attempt{} = attempt} <- fetch_attempt(attempt_id),
         {:ok, external_operation_ref} <- external_operation_ref(attempt, attrs),
         {:ok, task} <- build_task(attempt, external_operation_ref, attrs),
         :ok <- SecretGuard.validate_durable(task),
         {:ok, task, disposition} <- Stores.recovery_task_store().put_task(task),
         :ok <- maybe_append_discovery_event(disposition, attempt, task) do
      {:ok, task, disposition}
    end
  end

  @doc """
  Scans only pre-existing nonterminal rows, then reconciles due durable tasks.

  Hosts call this once when the owner restarts. Periodic work processes only
  tasks already in the durable queue so a healthy in-flight invocation is not
  mistaken for an orphan.
  """
  @spec reconcile_on_start(module(), keyword()) :: {:ok, summary()} | {:error, term()}
  def reconcile_on_start(observer, opts \\ []) do
    with :ok <- validate_observer(observer) do
      discovered =
        Stores.attempt_store().list_recoverable_attempts()
        |> Enum.reduce(0, fn attempt, count ->
          case put_outcome_unknown(attempt.attempt_id, %{now: now(opts)}) do
            {:ok, _task, :inserted} -> count + 1
            {:ok, _task, :existing} -> count
            {:error, :external_operation_ref_required} -> count
            {:error, _reason} -> count
          end
        end)

      with {:ok, due_summary} <- reconcile_due(observer, opts) do
        {:ok, Map.put(due_summary, :discovered, discovered)}
      end
    end
  end

  @spec reconcile_due(module(), keyword()) :: {:ok, summary()} | {:error, term()}
  def reconcile_due(observer, opts \\ []) do
    with :ok <- validate_observer(observer) do
      current_time = now(opts)
      limit = Keyword.get(opts, :limit, @default_limit)

      summary =
        current_time
        |> Stores.recovery_task_store().list_due(limit)
        |> Enum.reduce(empty_summary(), fn task, summary ->
          case reconcile_task(task.task_id, observer, opts) do
            {:ok, %RecoveryTask{status: :resolved}} ->
              %{summary | reconciled: summary.reconciled + 1}

            {:ok, %RecoveryTask{status: :quarantined}} ->
              %{summary | operator_required: summary.operator_required + 1}

            {:ok, %RecoveryTask{status: :pending}} ->
              %{summary | deferred: summary.deferred + 1}

            {:error, :not_claimable} ->
              summary

            {:error, _reason} ->
              %{summary | deferred: summary.deferred + 1}
          end
        end)

      {:ok, summary}
    end
  end

  @spec reconcile_task(String.t(), module(), keyword()) ::
          {:ok, RecoveryTask.t()} | {:error, term()}
  def reconcile_task(task_id, observer, opts \\ [])
      when is_binary(task_id) and is_atom(observer) do
    with :ok <- validate_observer(observer),
         {:ok, %RecoveryTask{} = task} <- fetch_task(task_id),
         :ok <- ensure_task_open(task),
         claim_ref <- Contracts.next_id("attempt-reconciliation-claim"),
         current_time <- now(opts),
         claim_expires_at <-
           DateTime.add(
             current_time,
             Keyword.get(opts, :claim_ttl_ms, @default_claim_ttl_ms),
             :millisecond
           ),
         {:ok, %RecoveryTask{} = claimed} <-
           Stores.recovery_task_store().claim_task(
             task_id,
             claim_ref,
             current_time,
             claim_expires_at
           ),
         {:ok, %Attempt{} = attempt} <- fetch_attempt(claimed.attempt_id) do
      reconcile_claimed(claimed, attempt, claim_ref, observer, current_time, opts)
    end
  end

  @spec task(String.t()) :: {:ok, RecoveryTask.t()} | :error
  def task(task_id) when is_binary(task_id), do: Stores.recovery_task_store().fetch_task(task_id)

  @spec tasks(map()) :: [RecoveryTask.t()]
  def tasks(filters \\ %{}) when is_map(filters),
    do: Stores.recovery_task_store().list_tasks(filters)

  defp reconcile_claimed(task, attempt, claim_ref, observer, current_time, opts) do
    cond do
      attempt.status in @terminal_attempt_statuses ->
        resolve_existing_terminal(task, attempt, claim_ref, current_time)

      deadline_elapsed?(task, current_time) ->
        close_and_quarantine(
          task,
          attempt,
          claim_ref,
          observer,
          current_time,
          "deadline_elapsed",
          opts
        )

      true ->
        case lease_posture(attempt, current_time) do
          :active ->
            observe(task, attempt, claim_ref, observer, current_time, opts)

          {:closed, reason} ->
            close_and_quarantine(
              task,
              attempt,
              claim_ref,
              observer,
              current_time,
              reason,
              opts
            )
        end
    end
  end

  defp observe(task, attempt, claim_ref, observer, current_time, opts) do
    context = observer_context(task, attempt)

    case observer.status(external_ref!(task), context) do
      {:ok, :active} ->
        defer(task, attempt, claim_ref, current_time, "active", nil, opts)

      {:ok, terminal} ->
        reduce_terminal(task, attempt, claim_ref, terminal, current_time, opts)

      {:error, :not_found} ->
        require_operator(task, attempt, claim_ref, current_time, "external_operation_not_found")

      {:error, reason} ->
        handle_observer_error(task, attempt, claim_ref, current_time, reason, opts)
    end
  end

  defp reduce_terminal(task, attempt, claim_ref, terminal, current_time, opts) do
    case normalize_terminal(terminal) do
      {:ok, :completed, payload} ->
        with :ok <- persist_terminal(attempt, :completed, payload),
             :ok <- append_recovery_event(attempt, "attempt.reconciliation.completed", payload) do
          transition_task(
            task,
            claim_ref,
            :resolved,
            current_time,
            %{
              "recovery_state" => "completed",
              "terminal_status" => "completed",
              "terminal_payload" => Redaction.redact(payload)
            }
          )
        end

      {:ok, terminal_status, payload} when terminal_status in [:failed, :cancelled] ->
        with :ok <- persist_terminal(attempt, :failed, payload),
             :ok <-
               append_recovery_event(
                 attempt,
                 "attempt.reconciliation.#{terminal_status}",
                 payload
               ) do
          transition_task(
            task,
            claim_ref,
            :resolved,
            current_time,
            %{
              "recovery_state" => Atom.to_string(terminal_status),
              "terminal_status" => Atom.to_string(terminal_status),
              "terminal_payload" => Redaction.redact(payload)
            }
          )
        end

      {:error, reason} ->
        handle_observer_error(task, attempt, claim_ref, current_time, reason, opts)
    end
  end

  defp resolve_existing_terminal(task, attempt, claim_ref, current_time) do
    with :ok <- converge_terminal_run(attempt) do
      transition_task(
        task,
        claim_ref,
        :resolved,
        current_time,
        %{
          "recovery_state" => "already_terminal",
          "terminal_status" => Atom.to_string(attempt.status)
        }
      )
    end
  end

  defp close_and_quarantine(
         task,
         attempt,
         claim_ref,
         observer,
         current_time,
         reason,
         _opts
       ) do
    context = Map.put(observer_context(task, attempt), :closure_reason, reason)
    cancel_result = observer.cancel(external_ref!(task), context)
    cleanup_result = observer.cleanup(external_ref!(task), context)

    payload = %{
      "recovery_state" => "operator_required",
      "reason" => reason,
      "cancel" => result_class(cancel_result),
      "cleanup" => result_class(cleanup_result)
    }

    with :ok <- persist_terminal(attempt, :failed, payload),
         :ok <-
           append_recovery_event(attempt, "attempt.reconciliation.operator_required", payload) do
      transition_task(task, claim_ref, :quarantined, current_time, payload)
    end
  end

  defp handle_observer_error(task, attempt, claim_ref, current_time, reason, opts) do
    retries = metadata_integer(task.metadata, "retry_count", 0) + 1
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    safe_reason = safe_reason(reason)

    if retries >= max_retries do
      require_operator(
        task,
        attempt,
        claim_ref,
        current_time,
        "observer_error_retry_limit",
        %{"last_error" => safe_reason, "retry_count" => retries}
      )
    else
      defer(task, attempt, claim_ref, current_time, "reconciling", safe_reason, opts)
    end
  end

  defp defer(task, attempt, claim_ref, current_time, state, safe_error, opts) do
    retries = metadata_integer(task.metadata, "retry_count", 0) + if(safe_error, do: 1, else: 0)
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms)
    due_at = DateTime.add(current_time, retry_delay_ms, :millisecond)

    metadata =
      %{
        "recovery_state" => state,
        "retry_count" => retries
      }
      |> maybe_put("last_error", safe_error)

    with :ok <-
           append_recovery_event(attempt, "attempt.reconciliation.deferred", %{
             "state" => state,
             "due_at" => DateTime.to_iso8601(due_at)
           }) do
      transition_task(task, claim_ref, :pending, due_at, metadata)
    end
  end

  defp require_operator(task, attempt, claim_ref, current_time, reason, metadata \\ %{}) do
    payload =
      metadata
      |> Map.merge(%{
        "recovery_state" => "operator_required",
        "reason" => reason
      })

    with :ok <- persist_terminal(attempt, :failed, payload),
         :ok <-
           append_recovery_event(attempt, "attempt.reconciliation.operator_required", payload) do
      transition_task(task, claim_ref, :quarantined, current_time, payload)
    end
  end

  defp persist_terminal(attempt, attempt_status, payload) do
    safe_payload = Redaction.redact(%{"reconciliation" => payload})

    with :ok <- SecretGuard.validate_durable(safe_payload),
         :ok <-
           Stores.attempt_store().update_attempt(
             attempt.attempt_id,
             attempt_status,
             safe_payload,
             attempt.runtime_ref_id,
             aggregator_opts(attempt)
           ),
         :ok <- persist_run_terminal(attempt.run_id, attempt_status, safe_payload) do
      :ok
    end
  end

  defp persist_run_terminal(run_id, :completed, payload),
    do: Stores.run_store().update_run(run_id, :completed, payload)

  defp persist_run_terminal(run_id, _failed, payload),
    do: Stores.run_store().update_run(run_id, :failed, payload)

  defp converge_terminal_run(attempt) do
    case Stores.run_store().fetch_run(attempt.run_id) do
      {:ok, %{status: status}} when status in [:completed, :failed] ->
        :ok

      {:ok, _nonterminal_run} ->
        persist_run_terminal(attempt.run_id, attempt.status, attempt.output || %{})

      :error ->
        {:error, :run_not_found}
    end
  end

  defp transition_task(task, claim_ref, status, due_at, metadata) do
    safe_metadata =
      task.metadata
      |> Map.merge(metadata)
      |> Redaction.redact()

    with :ok <- SecretGuard.validate_durable(safe_metadata) do
      Stores.recovery_task_store().transition_task(
        task.task_id,
        claim_ref,
        status,
        due_at,
        safe_metadata,
        Contracts.now()
      )
    end
  end

  defp append_recovery_event(attempt, type, payload) do
    event_store = Stores.event_store()
    seq = event_store.next_seq(attempt.run_id, attempt.attempt_id)

    event =
      Event.new!(%{
        event_id: Contracts.event_id(attempt.run_id, attempt.attempt_id, seq),
        run_id: attempt.run_id,
        attempt: attempt.attempt,
        attempt_id: attempt.attempt_id,
        seq: seq,
        type: type,
        stream: :control,
        level: if(String.ends_with?(type, "operator_required"), do: :warn, else: :info),
        payload: Redaction.redact(payload),
        runtime_ref_id: attempt.runtime_ref_id
      })

    event_store.append_events([event], aggregator_opts(attempt))
  end

  defp maybe_append_discovery_event(:existing, _attempt, _task), do: :ok

  defp maybe_append_discovery_event(:inserted, attempt, task) do
    append_recovery_event(attempt, "attempt.reconciliation.required", %{
      "task_id" => task.task_id,
      "recovery_state" => "outcome_unknown"
    })
  end

  defp build_task(attempt, external_operation_ref, attrs) do
    current_time = value(attrs, :now, Contracts.now())
    deadline_at = value(attrs, :deadline_at)

    controlled_metadata =
      %{
        "recovery_state" => "outcome_unknown",
        "external_operation_ref" => external_operation_ref,
        "credential_lease_id" => attempt.credential_lease_id,
        "deadline_at" => encode_datetime(deadline_at),
        "retry_count" => 0,
        "effect_retry" => "prohibited"
      }
      |> compact()

    metadata =
      attrs
      |> value(:metadata, %{})
      |> Map.new()
      |> Map.drop(@protected_metadata_keys)
      |> Map.merge(controlled_metadata)
      |> Redaction.redact()

    RecoveryTask.new(%{
      subject_ref: attempt.attempt_id,
      run_id: attempt.run_id,
      attempt_id: attempt.attempt_id,
      reason: "outcome_unknown",
      status: :pending,
      due_at: current_time,
      metadata: metadata,
      inserted_at: current_time,
      updated_at: current_time
    })
  end

  defp external_operation_ref(attempt, attrs) do
    case value(attrs, :external_operation_ref) || attempt.runtime_ref_id do
      ref when is_binary(ref) and ref != "" -> {:ok, ref}
      _missing -> {:error, :external_operation_ref_required}
    end
  end

  defp lease_posture(%Attempt{credential_lease_id: nil}, _now), do: :active

  defp lease_posture(%Attempt{credential_lease_id: lease_id}, current_time) do
    case Auth.lease_status(lease_id, %{now: current_time}) do
      {:ok, %{status: :active}} -> :active
      {:ok, %{status: status}} -> {:closed, "credential_lease_#{status}"}
      {:error, reason} -> {:closed, "credential_lease_#{safe_reason(reason)}"}
    end
  end

  defp deadline_elapsed?(task, current_time) do
    case task.metadata |> value(:deadline_at) |> parse_datetime() do
      {:ok, deadline} -> DateTime.compare(current_time, deadline) != :lt
      :error -> false
    end
  end

  defp observer_context(task, attempt) do
    %{
      task_id: task.task_id,
      run_id: attempt.run_id,
      attempt_id: attempt.attempt_id,
      credential_lease_id: attempt.credential_lease_id,
      external_operation_ref: external_ref!(task),
      effect_retry: :prohibited
    }
  end

  defp normalize_terminal({status, payload})
       when status in [:completed, :failed, :cancelled] and is_map(payload),
       do: {:ok, status, payload}

  defp normalize_terminal(%{status: status} = payload)
       when status in [:completed, :failed, :cancelled],
       do: {:ok, status, Map.delete(payload, :status)}

  defp normalize_terminal(%{"status" => status} = payload)
       when status in ["completed", "failed", "cancelled"] do
    {:ok, String.to_existing_atom(status), Map.delete(payload, "status")}
  end

  defp normalize_terminal(other), do: {:error, {:invalid_observer_terminal, safe_reason(other)}}

  defp result_class(:ok), do: "completed"
  defp result_class({:error, :not_found}), do: "not_found"
  defp result_class({:error, _reason}), do: "failed"
  defp result_class(_invalid), do: "invalid"

  defp validate_observer(observer) when is_atom(observer) do
    if Code.ensure_loaded?(observer) and
         Enum.all?([status: 2, cancel: 2, cleanup: 2], fn {fun, arity} ->
           function_exported?(observer, fun, arity)
         end) do
      :ok
    else
      {:error, :invalid_attempt_observer}
    end
  end

  defp fetch_attempt(attempt_id) do
    case Stores.attempt_store().fetch_attempt(attempt_id) do
      {:ok, %Attempt{} = attempt} -> {:ok, attempt}
      :error -> {:error, :attempt_not_found}
    end
  end

  defp fetch_task(task_id) do
    case Stores.recovery_task_store().fetch_task(task_id) do
      {:ok, %RecoveryTask{} = task} -> {:ok, task}
      :error -> {:error, :recovery_task_not_found}
    end
  end

  defp ensure_task_open(%RecoveryTask{status: status}) when status in @terminal_task_statuses,
    do: {:error, :recovery_task_terminal}

  defp ensure_task_open(%RecoveryTask{}), do: :ok

  defp external_ref!(task), do: value(task.metadata, :external_operation_ref)

  defp aggregator_opts(attempt) do
    [aggregator_id: attempt.aggregator_id, aggregator_epoch: attempt.aggregator_epoch]
  end

  defp empty_summary,
    do: %{discovered: 0, reconciled: 0, deferred: 0, operator_required: 0}

  defp now(opts), do: Keyword.get(opts, :now, Contracts.now())

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason(_reason), do: "observer_error"

  defp metadata_integer(metadata, key, default) do
    case value(metadata, key, default) do
      integer when is_integer(integer) and integer >= 0 -> integer
      _other -> default
    end
  end

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp encode_datetime(value) when is_binary(value), do: value

  defp parse_datetime(%DateTime{} = datetime), do: {:ok, datetime}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _invalid -> :error
    end
  end

  defp parse_datetime(_value), do: :error

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp value(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key), default)
  end
end
