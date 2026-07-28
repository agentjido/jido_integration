defmodule Jido.Integration.V2.StorePostgres.RecoveryTaskStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.RecoveryTaskStore

  import Ecto.Query

  alias Jido.Integration.V2.Auth.SecretGuard
  alias Jido.Integration.V2.RecoveryTask
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.RecoveryTaskRecord
  alias Jido.Integration.V2.StorePostgres.Serialization

  @impl true
  def put_task(%RecoveryTask{} = task) do
    with :ok <- SecretGuard.validate_durable(task) do
      attrs = to_record_attrs(task)

      Repo.transaction(fn ->
        {inserted_count, _rows} =
          Repo.insert_all(
            RecoveryTaskRecord,
            [attrs],
            on_conflict: :nothing,
            conflict_target: [:task_id]
          )

        disposition = if inserted_count == 1, do: :inserted, else: :existing
        load_existing!(task, disposition)
      end)
      |> case do
        {:ok, {persisted, disposition}} -> {:ok, persisted, disposition}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def fetch_task(task_id) do
    case Repo.get(RecoveryTaskRecord, task_id) do
      nil -> :error
      record -> {:ok, to_contract(record)}
    end
  end

  @impl true
  def list_tasks(filters) when is_map(filters) do
    RecoveryTaskRecord
    |> filter_query(filters)
    |> order_by([task], asc: task.due_at, asc: task.task_id)
    |> Repo.all()
    |> Enum.map(&to_contract/1)
  end

  @impl true
  def list_due(%DateTime{} = now, limit) when is_integer(limit) and limit > 0 do
    now = normalize_datetime(now)

    from(task in RecoveryTaskRecord,
      where:
        (task.status == :pending and task.due_at <= ^now) or
          (task.status == :running and task.claim_expires_at <= ^now),
      order_by: [asc: task.due_at, asc: task.task_id],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(&to_contract/1)
  end

  @impl true
  def claim_task(task_id, claim_ref, %DateTime{} = now, %DateTime{} = claim_expires_at)
      when is_binary(task_id) and is_binary(claim_ref) do
    now = normalize_datetime(now)
    claim_expires_at = normalize_datetime(claim_expires_at)

    query =
      from(task in RecoveryTaskRecord,
        where:
          task.task_id == ^task_id and
            ((task.status == :pending and task.due_at <= ^now) or
               (task.status == :running and task.claim_expires_at <= ^now))
      )

    case Repo.update_all(query,
           set: [
             status: :running,
             claim_ref: claim_ref,
             claim_expires_at: claim_expires_at,
             updated_at: now
           ],
           inc: [row_version: 1]
         ) do
      {1, _} ->
        fetch_task(task_id)

      {0, _} ->
        {:error, :not_claimable}
    end
  end

  @impl true
  def transition_task(
        task_id,
        claim_ref,
        status,
        %DateTime{} = due_at,
        metadata,
        %DateTime{} = now
      )
      when status in [:pending, :resolved, :quarantined] and is_map(metadata) do
    due_at = normalize_datetime(due_at)
    now = normalize_datetime(now)

    with :ok <- SecretGuard.validate_durable(metadata) do
      query =
        from(task in RecoveryTaskRecord,
          where:
            task.task_id == ^task_id and task.status == :running and
              task.claim_ref == ^claim_ref
        )

      case Repo.update_all(query,
             set: [
               status: status,
               due_at: due_at,
               metadata: Serialization.dump(metadata),
               claim_ref: nil,
               claim_expires_at: nil,
               updated_at: now
             ],
             inc: [row_version: 1]
           ) do
        {1, _} -> fetch_task(task_id)
        {0, _} -> {:error, :stale_recovery_claim}
      end
    end
  end

  def reset! do
    Repo.delete_all(RecoveryTaskRecord)
    :ok
  end

  defp load_existing!(task, disposition) do
    case Repo.get(RecoveryTaskRecord, task.task_id) do
      nil ->
        Repo.rollback(:recovery_task_conflict_without_row)

      record ->
        existing = to_contract(record)

        if same_identity?(existing, task) do
          {existing, disposition}
        else
          Repo.rollback(:recovery_task_conflict)
        end
    end
  end

  defp same_identity?(left, right) do
    left.subject_ref == right.subject_ref and
      left.run_id == right.run_id and
      left.attempt_id == right.attempt_id and
      left.reason == right.reason and
      external_ref(left) == external_ref(right)
  end

  defp external_ref(task) do
    Map.get(task.metadata, "external_operation_ref") ||
      Map.get(task.metadata, :external_operation_ref)
  end

  defp filter_query(query, filters) do
    Enum.reduce(filters, query, fn
      {:status, status}, query -> where(query, [task], task.status == ^status)
      {"status", status}, query -> where(query, [task], task.status == ^status)
      {:attempt_id, attempt_id}, query -> where(query, [task], task.attempt_id == ^attempt_id)
      {"attempt_id", attempt_id}, query -> where(query, [task], task.attempt_id == ^attempt_id)
      {:run_id, run_id}, query -> where(query, [task], task.run_id == ^run_id)
      {"run_id", run_id}, query -> where(query, [task], task.run_id == ^run_id)
      _unknown, query -> query
    end)
  end

  defp to_record_attrs(task) do
    %{
      task_id: task.task_id,
      subject_ref: task.subject_ref,
      run_id: task.run_id,
      attempt_id: task.attempt_id,
      route_id: task.route_id,
      receipt_id: task.receipt_id,
      reason: task.reason,
      status: task.status,
      due_at: normalize_datetime(task.due_at),
      metadata: Serialization.dump(task.metadata),
      row_version: 1,
      inserted_at: normalize_datetime(task.inserted_at),
      updated_at: normalize_datetime(task.updated_at)
    }
  end

  defp to_contract(record) do
    RecoveryTask.new!(%{
      task_id: record.task_id,
      subject_ref: record.subject_ref,
      run_id: record.run_id,
      attempt_id: record.attempt_id,
      route_id: record.route_id,
      receipt_id: record.receipt_id,
      reason: record.reason,
      status: record.status,
      due_at: record.due_at,
      metadata: Serialization.load_json(record.metadata),
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    })
  end

  defp normalize_datetime(%DateTime{microsecond: {microsecond, _precision}} = datetime),
    do: %DateTime{datetime | microsecond: {microsecond, 6}}
end
