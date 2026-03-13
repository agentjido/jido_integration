defmodule Jido.Integration.V2.StorePostgres.EventStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.EventStore

  import Ecto.Query

  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.AttemptRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.EventRecord
  alias Jido.Integration.V2.StorePostgres.Serialization

  @impl true
  def next_seq(run_id, attempt_id) do
    run_id
    |> position_query(attempt_key(run_id, attempt_id))
    |> select([event], max(event.seq))
    |> Repo.one()
    |> case do
      nil -> 0
      max_seq -> max_seq + 1
    end
  end

  @impl true
  def append_events([], _opts), do: :ok

  def append_events(events, opts) do
    Repo.transaction(fn ->
      assert_epoch!(events, opts)
      Enum.each(events, &persist_event!/1)
    end)
    |> normalize_transaction()
  end

  @impl true
  def list_events(run_id) do
    from(event in EventRecord,
      where: event.run_id == ^run_id,
      order_by: [asc_nulls_first: event.attempt, asc: event.seq, asc: event.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(&to_contract/1)
  end

  def reset! do
    Repo.delete_all(EventRecord)
    :ok
  end

  defp normalize_transaction({:ok, result}), do: result
  defp normalize_transaction({:error, reason}), do: {:error, reason}

  defp assert_epoch!([%Event{attempt_id: nil}], _opts), do: :ok
  defp assert_epoch!([%Event{attempt_id: nil} | _rest], _opts), do: :ok

  defp assert_epoch!([%Event{attempt_id: attempt_id} | _rest], opts) do
    record = fetch_attempt_record!(attempt_id)
    next_epoch = Keyword.get(opts, :aggregator_epoch, record.aggregator_epoch)
    next_id = Keyword.get(opts, :aggregator_id, record.aggregator_id)

    validate_epoch(record, attempt_id, next_epoch, next_id)
  end

  defp insert_event(%Event{} = event) do
    attrs = event_attrs(event)

    changeset = EventRecord.changeset(%EventRecord{}, attrs)

    case Repo.insert(changeset, mode: :savepoint) do
      {:ok, _record} ->
        :ok

      {:error, changeset} ->
        if unique_position_conflict?(changeset) do
          reconcile_duplicate(attrs)
        else
          {:error, changeset}
        end
    end
  end

  defp reconcile_duplicate(attrs) when is_map(attrs) do
    query = position_query(attrs.run_id, attrs.attempt_key)

    case Repo.one(from(existing in query, where: existing.seq == ^attrs.seq)) do
      nil ->
        {:error, :event_conflict}

      existing ->
        if matching_event?(existing, attrs) do
          :ok
        else
          {:error, :event_conflict}
        end
    end
  end

  defp event_attrs(%Event{} = event) do
    %{
      event_id: event.event_id,
      run_id: event.run_id,
      attempt: event.attempt,
      attempt_id: event.attempt_id,
      attempt_key: attempt_key(event.run_id, event.attempt_id),
      seq: event.seq,
      schema_version: event.schema_version,
      type: event.type,
      stream: event.stream,
      level: event.level,
      payload: event.payload |> Redaction.redact() |> Serialization.dump(),
      payload_ref:
        if(is_nil(event.payload_ref), do: nil, else: Serialization.dump(event.payload_ref)),
      trace: Serialization.dump(event.trace),
      target_id: event.target_id,
      session_id: event.session_id,
      runtime_ref_id: event.runtime_ref_id,
      ts: DateTime.truncate(event.ts, :microsecond)
    }
  end

  defp persist_event!(event) do
    case insert_event(event) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp fetch_attempt_record!(attempt_id) do
    case Repo.get(AttemptRecord, attempt_id) do
      nil -> Repo.rollback(:unknown_attempt)
      record -> record
    end
  end

  defp validate_epoch(record, _attempt_id, next_epoch, _next_id)
       when next_epoch < record.aggregator_epoch do
    Repo.rollback(:stale_aggregator_epoch)
  end

  defp validate_epoch(record, _attempt_id, next_epoch, next_id)
       when next_epoch == record.aggregator_epoch and next_id != record.aggregator_id do
    Repo.rollback(:aggregator_id_mismatch)
  end

  defp validate_epoch(record, attempt_id, next_epoch, next_id)
       when next_epoch > record.aggregator_epoch do
    advance_epoch!(attempt_id, next_epoch, next_id)
  end

  defp validate_epoch(_record, _attempt_id, _next_epoch, _next_id), do: :ok

  defp advance_epoch!(attempt_id, next_epoch, next_id) do
    case Repo.update_all(
           from(attempt in AttemptRecord,
             where: attempt.attempt_id == ^attempt_id and attempt.aggregator_epoch < ^next_epoch
           ),
           set: [aggregator_id: next_id, aggregator_epoch: next_epoch]
         ) do
      {1, _} -> :ok
      _ -> Repo.rollback(:stale_aggregator_epoch)
    end
  end

  defp matching_event?(record, attrs) do
    comparable_record_attrs(record) == comparable_event_attrs(attrs)
  end

  defp comparable_record_attrs(record) do
    %{
      event_id: record.event_id,
      run_id: record.run_id,
      attempt: record.attempt,
      attempt_id: record.attempt_id,
      attempt_key: record.attempt_key,
      seq: record.seq,
      schema_version: record.schema_version,
      type: record.type,
      stream: record.stream,
      level: record.level,
      payload: record.payload,
      payload_ref: record.payload_ref,
      trace: record.trace,
      target_id: record.target_id,
      session_id: record.session_id,
      runtime_ref_id: record.runtime_ref_id,
      ts: comparable_ts(record.ts)
    }
  end

  defp comparable_event_attrs(attrs) do
    attrs
    |> Map.take([
      :event_id,
      :run_id,
      :attempt,
      :attempt_id,
      :attempt_key,
      :seq,
      :schema_version,
      :type,
      :stream,
      :level,
      :payload,
      :payload_ref,
      :trace,
      :target_id,
      :session_id,
      :runtime_ref_id,
      :ts
    ])
    |> Map.update!(:ts, &comparable_ts/1)
  end

  defp comparable_ts(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)
  defp comparable_ts(value), do: value

  defp unique_position_conflict?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_message, metadata}} ->
      field == :seq and metadata[:constraint_name] == "run_events_position_index"
    end)
  end

  defp position_query(run_id, attempt_key) do
    from(event in EventRecord,
      where: event.run_id == ^run_id and event.attempt_key == ^attempt_key
    )
  end

  defp attempt_key(run_id, nil), do: "#{run_id}:run"
  defp attempt_key(_run_id, attempt_id), do: attempt_id

  defp to_contract(record) do
    Event.new!(%{
      event_id: record.event_id,
      schema_version: record.schema_version,
      run_id: record.run_id,
      attempt: record.attempt,
      attempt_id: record.attempt_id,
      seq: record.seq,
      type: record.type,
      stream: record.stream,
      level: record.level,
      payload: Serialization.load(record.payload || %{}),
      payload_ref: Serialization.load(record.payload_ref),
      trace: Serialization.load(record.trace || %{}),
      target_id: record.target_id,
      session_id: record.session_id,
      runtime_ref_id: record.runtime_ref_id,
      ts: record.ts
    })
  end
end
