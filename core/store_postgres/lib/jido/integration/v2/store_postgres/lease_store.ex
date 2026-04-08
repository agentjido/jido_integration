defmodule Jido.Integration.V2.StorePostgres.LeaseStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.LeaseStore

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
           :credential_id,
           :connection_id,
           :profile_id,
           :subject,
           :scopes,
           :payload_keys,
           :issued_at,
           :expires_at,
           :revoked_at,
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
           metadata: Serialization.load(record.metadata || %{})
         })}
    end
  end

  def reset! do
    StorePostgres.ensure_started!()
    Repo.delete_all(LeaseSchema)
    :ok
  end

  defp to_record_attrs(%AuthLeaseRecord{} = lease) do
    %{
      lease_id: lease.lease_id,
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
      metadata: Serialization.dump(lease.metadata)
    }
  end
end
