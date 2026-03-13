defmodule Jido.Integration.V2.StorePostgres.IngressStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.IngressStore

  import Ecto.Query

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.DedupeKeyRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.TriggerCheckpointRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.TriggerRecord, as: TriggerRecordSchema
  alias Jido.Integration.V2.StorePostgres.Serialization
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  @impl true
  def transaction(fun) when is_function(fun, 0) do
    case Repo.transaction(fn -> fun.() end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def rollback(reason) do
    Repo.rollback(reason)
  end

  @impl true
  def reserve_dedupe(tenant_id, connector_id, trigger_id, dedupe_key, expires_at) do
    attrs = %{
      tenant_id: tenant_id,
      connector_id: connector_id,
      trigger_id: trigger_id,
      dedupe_key: dedupe_key,
      expires_at: expires_at,
      inserted_at: Contracts.now()
    }

    %DedupeKeyRecord{}
    |> DedupeKeyRecord.changeset(attrs)
    |> Repo.insert(mode: :savepoint)
    |> case do
      {:ok, _record} ->
        :ok

      {:error, changeset} ->
        if duplicate_dedupe?(changeset) do
          {:error, :duplicate}
        else
          {:error, changeset}
        end
    end
  end

  @impl true
  def put_trigger(%TriggerRecord{} = trigger) do
    trigger
    |> to_trigger_attrs()
    |> then(&TriggerRecordSchema.changeset(%TriggerRecordSchema{}, &1))
    |> Repo.insert()
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def fetch_trigger(tenant_id, connector_id, trigger_id, dedupe_key) do
    query =
      from(record in TriggerRecordSchema,
        where:
          record.tenant_id == ^tenant_id and
            record.connector_id == ^connector_id and
            record.trigger_id == ^trigger_id and
            record.dedupe_key == ^dedupe_key,
        order_by: [desc: record.updated_at, desc: record.inserted_at],
        limit: 1
      )

    case Repo.one(query) do
      nil -> :error
      record -> {:ok, to_trigger_contract(record)}
    end
  end

  @impl true
  def list_run_triggers(run_id) do
    from(record in TriggerRecordSchema,
      where: record.run_id == ^run_id,
      order_by: [asc: record.inserted_at, asc: record.admission_id]
    )
    |> Repo.all()
    |> Enum.map(&to_trigger_contract/1)
  end

  @impl true
  def put_checkpoint(%TriggerCheckpoint{} = checkpoint) do
    query = checkpoint_query(checkpoint)

    case Repo.one(query) do
      nil ->
        insert_checkpoint(checkpoint)

      %TriggerCheckpointRecord{} = record ->
        update_checkpoint(query, record, checkpoint)
    end
  end

  @impl true
  def fetch_checkpoint(tenant_id, connector_id, trigger_id, partition_key) do
    query =
      from(record in TriggerCheckpointRecord,
        where:
          record.tenant_id == ^tenant_id and
            record.connector_id == ^connector_id and
            record.trigger_id == ^trigger_id and
            record.partition_key == ^partition_key
      )

    case Repo.one(query) do
      nil -> :error
      record -> {:ok, to_checkpoint_contract(record)}
    end
  end

  def reset! do
    Repo.delete_all(TriggerRecordSchema)
    Repo.delete_all(DedupeKeyRecord)
    Repo.delete_all(TriggerCheckpointRecord)
    :ok
  end

  defp duplicate_dedupe?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_message, metadata}} ->
      field == :dedupe_key and metadata[:constraint_name] == "dedupe_keys_scope_index"
    end)
  end

  defp to_trigger_attrs(%TriggerRecord{} = trigger) do
    %{
      admission_id: trigger.admission_id,
      tenant_id: trigger.tenant_id,
      connector_id: trigger.connector_id,
      trigger_id: trigger.trigger_id,
      capability_id: trigger.capability_id,
      source: trigger.source,
      external_id: trigger.external_id,
      dedupe_key: trigger.dedupe_key,
      partition_key: trigger.partition_key,
      payload: Serialization.dump(trigger.payload),
      signal: Serialization.dump(trigger.signal),
      status: trigger.status,
      run_id: trigger.run_id,
      rejection_reason: dump_reason(trigger.rejection_reason),
      inserted_at: trigger.inserted_at,
      updated_at: trigger.updated_at
    }
  end

  defp to_trigger_contract(record) do
    TriggerRecord.new!(%{
      admission_id: record.admission_id,
      source: record.source,
      connector_id: record.connector_id,
      trigger_id: record.trigger_id,
      capability_id: record.capability_id,
      tenant_id: record.tenant_id,
      external_id: record.external_id,
      dedupe_key: record.dedupe_key,
      partition_key: record.partition_key,
      payload: record.payload || %{},
      signal: record.signal || %{},
      status: record.status,
      run_id: record.run_id,
      rejection_reason: load_reason(record.rejection_reason),
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    })
  end

  defp to_checkpoint_attrs(%TriggerCheckpoint{} = checkpoint) do
    %{
      tenant_id: checkpoint.tenant_id,
      connector_id: checkpoint.connector_id,
      trigger_id: checkpoint.trigger_id,
      partition_key: checkpoint.partition_key,
      cursor: checkpoint.cursor,
      last_event_id: checkpoint.last_event_id,
      last_event_time: checkpoint.last_event_time,
      revision: checkpoint.revision,
      updated_at: checkpoint.updated_at
    }
  end

  defp checkpoint_query(%TriggerCheckpoint{} = checkpoint) do
    from(record in TriggerCheckpointRecord,
      where:
        record.tenant_id == ^checkpoint.tenant_id and
          record.connector_id == ^checkpoint.connector_id and
          record.trigger_id == ^checkpoint.trigger_id and
          record.partition_key == ^checkpoint.partition_key
    )
  end

  defp insert_checkpoint(%TriggerCheckpoint{} = checkpoint) do
    checkpoint
    |> to_checkpoint_attrs()
    |> then(&TriggerCheckpointRecord.changeset(%TriggerCheckpointRecord{}, &1))
    |> Repo.insert()
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp update_checkpoint(query, %TriggerCheckpointRecord{} = record, checkpoint) do
    case Repo.update_all(query, checkpoint_updates(record, checkpoint)) do
      {1, _records} -> :ok
      {_count, _records} -> {:error, :checkpoint_not_found}
    end
  end

  defp checkpoint_updates(record, checkpoint) do
    [
      set: [
        cursor: checkpoint.cursor,
        last_event_id: checkpoint.last_event_id,
        last_event_time: checkpoint.last_event_time,
        revision: record.revision + 1,
        updated_at: Contracts.now()
      ]
    ]
  end

  defp to_checkpoint_contract(record) do
    TriggerCheckpoint.new!(%{
      tenant_id: record.tenant_id,
      connector_id: record.connector_id,
      trigger_id: record.trigger_id,
      partition_key: record.partition_key,
      cursor: record.cursor,
      last_event_id: record.last_event_id,
      last_event_time: record.last_event_time,
      revision: record.revision,
      updated_at: record.updated_at
    })
  end

  defp dump_reason(nil), do: nil
  defp dump_reason(reason), do: :erlang.term_to_binary(reason)

  defp load_reason(nil), do: nil
  defp load_reason(reason), do: :erlang.binary_to_term(reason)
end
