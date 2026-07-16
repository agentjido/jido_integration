defmodule Jido.Integration.V2.StorePostgres.LeaseStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.LeaseStore

  import Ecto.Query

  alias Jido.Integration.V2.Auth.LeaseRecord, as: AuthLeaseRecord
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.LeaseRecord, as: LeaseSchema
  alias Jido.Integration.V2.StorePostgres.Serialization

  @impl true
  def store_lease(%AuthLeaseRecord{} = lease) do
    lease
    |> to_record_attrs()
    |> then(&LeaseSchema.changeset(%LeaseSchema{}, &1))
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :credential_ref_id,
           :tenant_id,
           :credential_id,
           :connection_id,
           :profile_id,
           :subject,
           :scopes,
           :payload_keys,
           :issued_at,
           :expires_at,
           :revoked_at,
           :redemption_count,
           :last_redeemed_at,
           :last_materialization_ref,
           :metadata
         ]},
      conflict_target: [:lease_id]
    )
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def fetch_lease(id) do
    case Repo.get(LeaseSchema, id) do
      nil ->
        {:error, :unknown_lease}

      record ->
        {:ok,
         AuthLeaseRecord.new!(%{
           lease_id: record.lease_id,
           tenant_id: record.tenant_id,
           credential_ref_id: record.credential_ref_id,
           credential_id: record.credential_id,
           connection_id: record.connection_id,
           profile_id: record.profile_id,
           subject: record.subject,
           scopes: record.scopes || [],
           payload_keys: record.payload_keys || [],
           issued_at: record.issued_at,
           expires_at: record.expires_at,
           revoked_at: record.revoked_at,
           redemption_count: record.redemption_count || 0,
           last_redeemed_at: record.last_redeemed_at,
           last_materialization_ref: record.last_materialization_ref,
           metadata: Serialization.load(record.metadata || %{})
         })}
    end
  end

  @impl true
  def record_redemption(id, now, max_calls) do
    Repo.transaction(fn ->
      record = lock_lease!(id)

      cond do
        record.revoked_at != nil ->
          Repo.rollback(:revoked_lease)

        DateTime.compare(record.expires_at, now) != :gt ->
          Repo.rollback(:expired_lease)

        max_calls != :unlimited and record.redemption_count >= max_calls ->
          Repo.rollback(:max_calls_exceeded)

        true ->
          case record
               |> LeaseSchema.changeset(%{
                 redemption_count: record.redemption_count + 1,
                 last_redeemed_at: now
               })
               |> Repo.update() do
            {:ok, updated} -> to_auth_record(updated)
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
    |> normalize_transaction()
  end

  @impl true
  def record_materialization(id, materialization_ref, now) do
    Repo.transaction(fn ->
      record = lock_lease!(id)

      case record
           |> LeaseSchema.changeset(%{
             last_materialization_ref: materialization_ref,
             metadata:
               record.metadata
               |> Serialization.load()
               |> Map.put(:last_materialized_at, now)
               |> Serialization.dump()
           })
           |> Repo.update() do
        {:ok, updated} -> to_auth_record(updated)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction()
  end

  def reset! do
    StorePostgres.assert_started!()
    Repo.delete_all(LeaseSchema)
    :ok
  end

  defp to_record_attrs(%AuthLeaseRecord{} = lease) do
    %{
      lease_id: lease.lease_id,
      tenant_id: lease.tenant_id,
      credential_ref_id: lease.credential_ref_id,
      credential_id: lease.credential_id,
      connection_id: lease.connection_id,
      profile_id: lease.profile_id,
      subject: lease.subject,
      scopes: lease.scopes,
      payload_keys: lease.payload_keys,
      issued_at: lease.issued_at,
      expires_at: lease.expires_at,
      revoked_at: lease.revoked_at,
      redemption_count: lease.redemption_count,
      last_redeemed_at: lease.last_redeemed_at,
      last_materialization_ref: lease.last_materialization_ref,
      metadata: Serialization.dump(lease.metadata)
    }
  end

  defp lock_lease!(id) do
    case Repo.one(from(lease in LeaseSchema, where: lease.lease_id == ^id, lock: "FOR UPDATE")) do
      nil -> Repo.rollback(:unknown_lease)
      record -> record
    end
  end

  defp to_auth_record(record) do
    AuthLeaseRecord.new!(%{
      lease_id: record.lease_id,
      tenant_id: record.tenant_id,
      credential_ref_id: record.credential_ref_id,
      credential_id: record.credential_id,
      connection_id: record.connection_id,
      profile_id: record.profile_id,
      subject: record.subject,
      scopes: record.scopes || [],
      payload_keys: record.payload_keys || [],
      issued_at: record.issued_at,
      expires_at: record.expires_at,
      revoked_at: record.revoked_at,
      redemption_count: record.redemption_count || 0,
      last_redeemed_at: record.last_redeemed_at,
      last_materialization_ref: record.last_materialization_ref,
      metadata: Serialization.load(record.metadata || %{})
    })
  end

  defp normalize_transaction({:ok, result}), do: {:ok, result}
  defp normalize_transaction({:error, reason}), do: {:error, reason}
end
