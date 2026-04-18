defmodule Jido.Integration.V2.StorePostgres.ClaimCheckStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.ClaimCheckStore

  import Ecto.Query

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane.ClaimCheckTelemetry
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.ClaimCheckBlobRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.ClaimCheckReferenceRecord

  @impl true
  def stage_blob(payload_ref, encoded, metadata) when is_binary(encoded) and is_map(metadata) do
    payload_ref = normalize_payload_ref(payload_ref)
    ensure_blob_path!(payload_ref, encoded)
    now = Contracts.now()

    attrs = %{
      store: payload_ref.store,
      key: payload_ref.key,
      checksum: payload_ref.checksum,
      size_bytes: payload_ref.size_bytes,
      content_type: metadata.content_type,
      redaction_class: metadata.redaction_class,
      status: :staged,
      trace_id: metadata[:trace_id],
      payload_kind: maybe_stringify(metadata[:payload_kind]),
      staged_at: now,
      inserted_at: now,
      updated_at: now
    }

    %ClaimCheckBlobRecord{}
    |> ClaimCheckBlobRecord.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          checksum: attrs.checksum,
          size_bytes: attrs.size_bytes,
          content_type: attrs.content_type,
          redaction_class: attrs.redaction_class,
          status: :staged,
          trace_id: attrs.trace_id,
          payload_kind: attrs.payload_kind,
          staged_at: attrs.staged_at,
          updated_at: attrs.updated_at
        ]
      ],
      conflict_target: [:store, :key]
    )
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def fetch_blob(payload_ref) do
    payload_ref = normalize_payload_ref(payload_ref)
    path = blob_path(payload_ref)

    case File.read(path) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, :enoent} -> :error
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def register_reference(payload_ref, attrs) when is_map(attrs) do
    payload_ref = normalize_payload_ref(payload_ref)
    timestamp = Contracts.now()

    Repo.transaction(fn ->
      case insert_reference(payload_ref, attrs, timestamp) do
        {:ok, _record} ->
          :ok

        {:error, changeset} ->
          Repo.rollback(changeset)
      end

      case mark_blob_referenced(payload_ref, timestamp) do
        {count, _rows} when count >= 1 ->
          :ok

        {0, _rows} ->
          Repo.rollback(:missing_staged_blob)
      end

      :ok
    end)
    |> normalize_transaction()
  end

  @impl true
  def fetch_blob_metadata(payload_ref) do
    payload_ref = normalize_payload_ref(payload_ref)

    case Repo.one(
           from(blob in ClaimCheckBlobRecord,
             where: blob.store == ^payload_ref.store and blob.key == ^payload_ref.key
           )
         ) do
      nil -> :error
      blob -> {:ok, blob_metadata(blob)}
    end
  end

  @impl true
  def count_live_references(payload_ref) do
    payload_ref = normalize_payload_ref(payload_ref)

    from(reference in ClaimCheckReferenceRecord,
      where: reference.store == ^payload_ref.store and reference.key == ^payload_ref.key,
      select: count(reference.id)
    )
    |> Repo.one()
  end

  @impl true
  def sweep_staged_payloads(opts \\ []) do
    older_than_s = Keyword.get(opts, :older_than_s, 0)
    cutoff = DateTime.add(Contracts.now(), -older_than_s, :second)

    blobs =
      from(blob in ClaimCheckBlobRecord,
        where: blob.status == :staged and blob.staged_at <= ^cutoff
      )
      |> Repo.all()

    deleted_count =
      Enum.reduce(blobs, 0, fn blob, count ->
        if live_references?(blob) do
          count
        else
          ClaimCheckTelemetry.orphaned_staged_payload(
            %{
              store: blob.store,
              key: blob.key,
              checksum: blob.checksum,
              size_bytes: blob.size_bytes
            },
            blob_metadata(blob),
            source_component: :store_postgres,
            store_backend: :store_postgres
          )

          delete_blob_file(%{store: blob.store, key: blob.key})

          Repo.update_all(
            from(record in ClaimCheckBlobRecord, where: record.id == ^blob.id),
            set: [status: :swept, deleted_at: Contracts.now(), updated_at: Contracts.now()]
          )

          count + 1
        end
      end)

    {:ok, %{deleted_count: deleted_count}}
  end

  @impl true
  def garbage_collect(opts \\ []) do
    older_than_s = Keyword.get(opts, :older_than_s, 0)
    cutoff = DateTime.add(Contracts.now(), -older_than_s, :second)

    blobs =
      from(blob in ClaimCheckBlobRecord,
        where: blob.status in [:staged, :referenced, :swept] and blob.staged_at <= ^cutoff
      )
      |> Repo.all()

    {deleted_count, skipped_live_reference_count} =
      Enum.reduce(blobs, {0, 0}, fn blob, {deleted, skipped} ->
        if live_references?(blob) do
          ClaimCheckTelemetry.blob_gc_skipped_live_reference(
            %{
              store: blob.store,
              key: blob.key,
              checksum: blob.checksum,
              size_bytes: blob.size_bytes
            },
            blob_metadata(blob),
            source_component: :store_postgres,
            store_backend: :store_postgres,
            live_reference_count: count_live_references(%{store: blob.store, key: blob.key})
          )

          {deleted, skipped + 1}
        else
          ClaimCheckTelemetry.blob_gc_deleted(
            %{
              store: blob.store,
              key: blob.key,
              checksum: blob.checksum,
              size_bytes: blob.size_bytes
            },
            blob_metadata(blob),
            source_component: :store_postgres,
            store_backend: :store_postgres
          )

          delete_blob_file(%{store: blob.store, key: blob.key})

          Repo.update_all(
            from(record in ClaimCheckBlobRecord, where: record.id == ^blob.id),
            set: [status: :deleted, deleted_at: Contracts.now(), updated_at: Contracts.now()]
          )

          {deleted + 1, skipped}
        end
      end)

    {:ok,
     %{
       deleted_count: deleted_count,
       skipped_live_reference_count: skipped_live_reference_count
     }}
  end

  def reset! do
    StorePostgres.assert_started!()
    Repo.delete_all(ClaimCheckReferenceRecord)
    Repo.delete_all(ClaimCheckBlobRecord)
    File.rm_rf!(root_path())
    :ok
  end

  defp normalize_transaction({:ok, :ok}), do: :ok
  defp normalize_transaction({:error, reason}), do: {:error, reason}

  defp insert_reference(payload_ref, attrs, timestamp) do
    %ClaimCheckReferenceRecord{}
    |> ClaimCheckReferenceRecord.changeset(%{
      store: payload_ref.store,
      key: payload_ref.key,
      ledger_kind: maybe_stringify(attrs[:ledger_kind]),
      ledger_id: attrs[:ledger_id],
      payload_field: maybe_stringify(attrs[:payload_field]),
      run_id: attrs[:run_id],
      attempt_id: attrs[:attempt_id],
      event_id: attrs[:event_id],
      trace_id: attrs[:trace_id],
      inserted_at: timestamp
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:ledger_kind, :ledger_id, :payload_field]
    )
  end

  defp mark_blob_referenced(payload_ref, timestamp) do
    Repo.update_all(
      from(blob in ClaimCheckBlobRecord,
        where: blob.store == ^payload_ref.store and blob.key == ^payload_ref.key
      ),
      set: [status: :referenced, referenced_at: timestamp, updated_at: timestamp]
    )
  end

  defp live_references?(blob) do
    Repo.exists?(
      from(reference in ClaimCheckReferenceRecord,
        where: reference.store == ^blob.store and reference.key == ^blob.key
      )
    )
  end

  defp blob_metadata(blob) do
    %{
      store: blob.store,
      key: blob.key,
      checksum: blob.checksum,
      size_bytes: blob.size_bytes,
      content_type: blob.content_type,
      redaction_class: blob.redaction_class,
      status: blob.status,
      trace_id: blob.trace_id,
      payload_kind: blob.payload_kind,
      staged_at: blob.staged_at,
      referenced_at: blob.referenced_at,
      deleted_at: blob.deleted_at
    }
  end

  defp ensure_blob_path!(payload_ref, encoded) do
    path = blob_path(payload_ref)
    File.mkdir_p!(Path.dirname(path))

    if File.exists?(path) do
      :ok
    else
      tmp_path = "#{path}.tmp-#{System.unique_integer([:positive])}"
      File.write!(tmp_path, encoded)

      case File.rename(tmp_path, path) do
        :ok ->
          :ok

        {:error, :eexist} ->
          File.rm(tmp_path)
          :ok

        {:error, reason} ->
          File.rm(tmp_path)
          raise File.Error, reason: reason, action: "rename", path: path
      end
    end
  end

  defp delete_blob_file(payload_ref) do
    case File.rm(blob_path(payload_ref)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp blob_path(payload_ref) do
    Path.join(root_path(), Path.join([payload_ref.store, payload_ref.key <> ".json"]))
  end

  defp root_path do
    Application.get_env(
      :jido_integration_v2_store_postgres,
      :claim_check_root,
      default_root_path()
    )
  end

  defp default_root_path do
    Path.join(
      System.tmp_dir!(),
      Path.join("jido_integration_v2_claim_check", current_database_name())
    )
  end

  defp current_database_name do
    Application.get_env(:jido_integration_v2_store_postgres, Repo, [])[:database] ||
      System.get_env("JIDO_INTEGRATION_V2_DB_NAME", "jido_integration_v2_dev")
  end

  defp maybe_stringify(nil), do: nil
  defp maybe_stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_stringify(value), do: to_string(value)

  defp normalize_payload_ref(payload_ref) when is_map(payload_ref) do
    %{
      store: payload_ref[:store] || payload_ref["store"],
      key: payload_ref[:key] || payload_ref["key"],
      checksum: payload_ref[:checksum] || payload_ref["checksum"],
      size_bytes: payload_ref[:size_bytes] || payload_ref["size_bytes"],
      ttl_s: payload_ref[:ttl_s] || payload_ref["ttl_s"],
      access_control: payload_ref[:access_control] || payload_ref["access_control"]
    }
  end
end
