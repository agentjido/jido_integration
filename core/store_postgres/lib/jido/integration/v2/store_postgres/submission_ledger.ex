defmodule Jido.Integration.V2.StorePostgres.SubmissionLedger do
  @moduledoc false

  @behaviour Jido.Integration.V2.BrainIngress.SubmissionLedger

  import Ecto.Query

  alias Jido.Integration.V2.BrainIngress.SubmissionDedupe
  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.StorePostgres.Repo

  alias Jido.Integration.V2.StorePostgres.Schemas.{
    ExpiredSubmissionRecord,
    SubmissionRecord
  }

  alias Jido.Integration.V2.StorePostgres.Serialization
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionIdentity
  alias Jido.Integration.V2.SubmissionRejection

  @retention_days 14

  @impl true
  def accept_submission(%BrainInvocation{} = invocation, opts) do
    tenant_id = invocation.tenant_id
    submission_dedupe_key = SubmissionDedupe.key!(invocation)
    identity_checksum = SubmissionIdentity.submission_key(invocation.submission_identity)
    now = now(opts)
    expires_at = expires_at(now, opts)

    if archived_submission?(tenant_id, submission_dedupe_key) do
      {:error, :expired_submission_dedupe_key}
    else
      acceptance =
        SubmissionAcceptance.new!(%{
          submission_key: invocation.submission_key,
          submission_receipt_ref: "submission://postgres/#{invocation.submission_key}",
          status: :accepted,
          accepted_at: now,
          ledger_version: 1
        })

      attrs = %{
        submission_key: invocation.submission_key,
        tenant_id: tenant_id,
        submission_dedupe_key: submission_dedupe_key,
        identity_checksum: identity_checksum,
        status: "accepted",
        acceptance_json: Serialization.dump(SubmissionAcceptance.dump(acceptance)),
        rejection_json: nil,
        last_seen_at: now,
        expires_at: expires_at
      }

      insert_acceptance(
        attrs,
        acceptance,
        tenant_id,
        submission_dedupe_key,
        identity_checksum,
        now,
        expires_at
      )
    end
  end

  @impl true
  def lookup_submission(submission_dedupe_key, tenant_id, opts)
      when is_binary(submission_dedupe_key) and is_binary(tenant_id) do
    now = now(opts)

    case fetch_live_record(tenant_id, submission_dedupe_key) do
      %SubmissionRecord{} = record ->
        if expired?(record, now) do
          {:expired, record.last_seen_at || now}
        else
          decode_live_lookup(record)
        end

      nil ->
        case latest_expired_record(tenant_id, submission_dedupe_key) do
          %ExpiredSubmissionRecord{last_seen_at: %DateTime{} = last_seen_at} ->
            {:expired, last_seen_at}

          _other ->
            :never_seen
        end
    end
  end

  @impl true
  def fetch_acceptance(submission_key, opts) do
    authorized_tenant_id = Keyword.get(opts, :tenant_id)

    submission_key
    |> fetch_record_by_submission_key()
    |> case do
      %SubmissionRecord{tenant_id: tenant_id, acceptance_json: acceptance_json}
      when is_map(acceptance_json) ->
        with :ok <- authorize_tenant(tenant_id, authorized_tenant_id) do
          {:ok, acceptance_json |> Serialization.load_json() |> SubmissionAcceptance.new!()}
        end

      %ExpiredSubmissionRecord{tenant_id: tenant_id, acceptance_json: acceptance_json}
      when is_map(acceptance_json) ->
        with :ok <- authorize_tenant(tenant_id, authorized_tenant_id) do
          {:ok, acceptance_json |> Serialization.load_json() |> SubmissionAcceptance.new!()}
        end

      _other ->
        :error
    end
  end

  defp authorize_tenant(_record_tenant_id, nil), do: :ok
  defp authorize_tenant(tenant_id, tenant_id), do: :ok
  defp authorize_tenant(_record_tenant_id, _authorized_tenant_id), do: {:error, :tenant_mismatch}

  @impl true
  def record_rejection(%BrainInvocation{} = invocation, %SubmissionRejection{} = rejection, opts) do
    tenant_id = invocation.tenant_id
    submission_dedupe_key = SubmissionDedupe.key!(invocation)
    identity_checksum = SubmissionIdentity.submission_key(invocation.submission_identity)
    now = now(opts)
    expires_at = expires_at(now, opts)

    if archived_submission?(tenant_id, submission_dedupe_key) do
      {:error, :expired_submission_dedupe_key}
    else
      attrs = %{
        submission_key: invocation.submission_key,
        tenant_id: tenant_id,
        submission_dedupe_key: submission_dedupe_key,
        identity_checksum: identity_checksum,
        status: "rejected",
        acceptance_json: nil,
        rejection_json: Serialization.dump(SubmissionRejection.dump(rejection)),
        last_seen_at: now,
        expires_at: expires_at
      }

      upsert_rejection(
        fetch_live_record(tenant_id, submission_dedupe_key),
        attrs,
        identity_checksum
      )
    end
  end

  @impl true
  def expire_submissions(opts) do
    now = now(opts)

    Repo.transaction(fn ->
      Repo.all(from(record in SubmissionRecord, where: record.expires_at <= ^now))
      |> Enum.reduce(0, fn record, count ->
        archive_record!(record, now)
        Repo.delete!(record)
        count + 1
      end)
    end)
    |> case do
      {:ok, count} -> count
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_live_lookup(%SubmissionRecord{status: "accepted", acceptance_json: acceptance_json})
       when is_map(acceptance_json) do
    {:accepted, acceptance_json |> Serialization.load_json() |> SubmissionAcceptance.new!()}
  end

  defp decode_live_lookup(%SubmissionRecord{status: "rejected", rejection_json: rejection_json})
       when is_map(rejection_json) do
    {:rejected, rejection_json |> Serialization.load_json() |> SubmissionRejection.new!()}
  end

  defp decode_live_lookup(_record), do: :never_seen

  defp fetch_live_record(tenant_id, submission_dedupe_key) do
    Repo.get_by(SubmissionRecord,
      tenant_id: tenant_id,
      submission_dedupe_key: submission_dedupe_key
    )
  end

  defp latest_expired_record(tenant_id, submission_dedupe_key) do
    ExpiredSubmissionRecord
    |> where(
      [record],
      record.tenant_id == ^tenant_id and
        record.submission_dedupe_key == ^submission_dedupe_key
    )
    |> order_by([record], desc: record.expired_at)
    |> limit(1)
    |> Repo.one()
  end

  defp fetch_record_by_submission_key(submission_key) do
    Repo.get(SubmissionRecord, submission_key) ||
      Repo.one(
        from(record in ExpiredSubmissionRecord,
          where: record.submission_key == ^submission_key,
          order_by: [desc: record.expired_at],
          limit: 1
        )
      )
  end

  defp archived_submission?(tenant_id, submission_dedupe_key) do
    ExpiredSubmissionRecord
    |> where(
      [record],
      record.tenant_id == ^tenant_id and
        record.submission_dedupe_key == ^submission_dedupe_key
    )
    |> select([record], count(record.id))
    |> Repo.one()
    |> Kernel.>(0)
  end

  defp refresh_retention_window(%SubmissionRecord{} = record, now, expires_at) do
    record
    |> SubmissionRecord.changeset(%{last_seen_at: now, expires_at: expires_at})
    |> Repo.update()
  end

  defp insert_acceptance(
         attrs,
         acceptance,
         tenant_id,
         submission_dedupe_key,
         identity_checksum,
         now,
         expires_at
       ) do
    case Repo.insert(SubmissionRecord.changeset(%SubmissionRecord{}, attrs)) do
      {:ok, _record} ->
        {:ok, acceptance}

      {:error, changeset} ->
        reconcile_duplicate_acceptance(
          changeset,
          tenant_id,
          submission_dedupe_key,
          identity_checksum,
          now,
          expires_at
        )
    end
  end

  defp reconcile_duplicate_acceptance(
         changeset,
         tenant_id,
         submission_dedupe_key,
         identity_checksum,
         now,
         expires_at
       ) do
    if duplicate_dedupe?(changeset) or duplicate_submission_key?(changeset) do
      with %SubmissionRecord{} = record <- fetch_live_record(tenant_id, submission_dedupe_key),
           true <- record.identity_checksum == identity_checksum,
           true <- record.status == "accepted",
           {:ok, refreshed} <- refresh_retention_window(record, now, expires_at) do
        duplicate =
          refreshed.acceptance_json
          |> Serialization.load_json()
          |> SubmissionAcceptance.new!()
          |> SubmissionAcceptance.dump()
          |> Map.put(:status, :duplicate)
          |> SubmissionAcceptance.new!()

        {:ok, duplicate}
      else
        _other -> {:error, :conflicting_submission}
      end
    else
      {:error, changeset}
    end
  end

  defp upsert_rejection(nil, attrs, _identity_checksum) do
    persist_rejection(%SubmissionRecord{}, attrs, &Repo.insert/1)
  end

  defp upsert_rejection(%SubmissionRecord{} = record, attrs, identity_checksum) do
    if record.identity_checksum == identity_checksum do
      persist_rejection(record, attrs, &Repo.update/1)
    else
      {:error, :conflicting_submission}
    end
  end

  defp persist_rejection(record, attrs, persistence_fun) do
    record
    |> SubmissionRecord.changeset(attrs)
    |> persistence_fun.()
    |> case do
      {:ok, _record} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp archive_record!(%SubmissionRecord{} = record, expired_at) do
    %ExpiredSubmissionRecord{}
    |> ExpiredSubmissionRecord.changeset(%{
      submission_key: record.submission_key,
      tenant_id: record.tenant_id,
      submission_dedupe_key: record.submission_dedupe_key,
      identity_checksum: record.identity_checksum,
      status: record.status,
      acceptance_json: record.acceptance_json,
      rejection_json: record.rejection_json,
      last_seen_at: record.last_seen_at || record.updated_at || expired_at,
      expired_at: expired_at
    })
    |> Repo.insert!()
  end

  defp expired?(%SubmissionRecord{expires_at: %DateTime{} = expires_at}, now) do
    DateTime.compare(expires_at, now) != :gt
  end

  defp expired?(%SubmissionRecord{}, _now), do: false

  defp now(opts), do: Keyword.get(opts, :now, Contracts.now())

  defp expires_at(now, opts) do
    retention_days = Keyword.get(opts, :retention_days, @retention_days)
    DateTime.add(now, retention_days * 86_400, :second)
  end

  defp duplicate_submission_key?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_message, metadata}} ->
      field == :submission_key and metadata[:constraint] in [:unique, :unsafe_unique]
    end)
  end

  defp duplicate_dedupe?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_message, metadata}} ->
      field == :submission_dedupe_key and metadata[:constraint] in [:unique, :unsafe_unique]
    end)
  end
end
