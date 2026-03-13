defmodule Jido.Integration.V2.StorePostgres.LeaseStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.LeaseStore

  alias Jido.Integration.V2.Auth.LeaseRecord, as: AuthLeaseRecord
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.LeaseRecord, as: LeaseSchema
  alias Jido.Integration.V2.StorePostgres.Serialization

  @impl true
  def store_lease(%AuthLeaseRecord{} = lease) do
    lease
    |> to_record_attrs()
    |> then(&LeaseSchema.changeset(%LeaseSchema{}, &1))
    |> Repo.insert(
      on_conflict: {:replace, [:payload_keys, :expires_at, :revoked_at, :metadata]},
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
           connection_id: record.connection_id,
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
    Repo.delete_all(LeaseSchema)
    :ok
  end

  defp to_record_attrs(%AuthLeaseRecord{} = lease) do
    %{
      lease_id: lease.lease_id,
      credential_ref_id: lease.credential_ref_id,
      connection_id: lease.connection_id,
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
