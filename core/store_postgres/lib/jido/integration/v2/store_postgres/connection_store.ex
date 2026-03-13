defmodule Jido.Integration.V2.StorePostgres.ConnectionStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.ConnectionStore

  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.ConnectionRecord
  alias Jido.Integration.V2.StorePostgres.Serialization

  @impl true
  def store_connection(%Connection{} = connection) do
    attrs =
      %{
        connection_id: connection.connection_id,
        tenant_id: connection.tenant_id,
        connector_id: connection.connector_id,
        auth_type: Atom.to_string(connection.auth_type),
        subject: connection.subject,
        state: Atom.to_string(connection.state),
        credential_ref_id: connection.credential_ref_id,
        install_id: connection.install_id,
        requested_scopes: connection.requested_scopes,
        granted_scopes: connection.granted_scopes,
        lease_fields: connection.lease_fields,
        token_expires_at: connection.token_expires_at,
        last_rotated_at: connection.last_rotated_at,
        revoked_at: connection.revoked_at,
        revocation_reason: connection.revocation_reason,
        actor_id: connection.actor_id,
        metadata: Serialization.dump(connection.metadata),
        inserted_at: connection.inserted_at || Contracts.now(),
        updated_at: connection.updated_at || Contracts.now()
      }

    %ConnectionRecord{}
    |> ConnectionRecord.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :tenant_id,
           :connector_id,
           :auth_type,
           :subject,
           :state,
           :credential_ref_id,
           :install_id,
           :requested_scopes,
           :granted_scopes,
           :lease_fields,
           :token_expires_at,
           :last_rotated_at,
           :revoked_at,
           :revocation_reason,
           :actor_id,
           :metadata,
           :updated_at
         ]},
      conflict_target: [:connection_id]
    )
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def fetch_connection(connection_id) do
    case Repo.get(ConnectionRecord, connection_id) do
      nil ->
        {:error, :unknown_connection}

      record ->
        {:ok,
         Connection.new!(%{
           connection_id: record.connection_id,
           tenant_id: record.tenant_id,
           connector_id: record.connector_id,
           auth_type: String.to_existing_atom(record.auth_type),
           subject: record.subject,
           state: String.to_existing_atom(record.state),
           credential_ref_id: record.credential_ref_id,
           install_id: record.install_id,
           requested_scopes: record.requested_scopes || [],
           granted_scopes: record.granted_scopes || [],
           lease_fields: record.lease_fields || [],
           token_expires_at: record.token_expires_at,
           last_rotated_at: record.last_rotated_at,
           revoked_at: record.revoked_at,
           revocation_reason: record.revocation_reason,
           actor_id: record.actor_id,
           metadata: Serialization.load(record.metadata || %{}),
           inserted_at: record.inserted_at,
           updated_at: record.updated_at
         })}
    end
  end

  def reset! do
    Repo.delete_all(ConnectionRecord)
    :ok
  end
end
