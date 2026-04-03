defmodule Jido.Integration.V2.StorePostgres.ConnectionStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.ConnectionStore

  import Ecto.Query

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
        profile_id: connection.profile_id,
        subject: connection.subject,
        state: Atom.to_string(connection.state),
        credential_ref_id: connection.credential_ref_id,
        current_credential_ref_id: connection.current_credential_ref_id,
        current_credential_id: connection.current_credential_id,
        install_id: connection.install_id,
        management_mode: dump_optional_atom(connection.management_mode),
        secret_source: dump_optional_atom(connection.secret_source),
        external_secret_ref: dump_optional_map(connection.external_secret_ref),
        requested_scopes: connection.requested_scopes,
        granted_scopes: connection.granted_scopes,
        lease_fields: connection.lease_fields,
        token_expires_at: connection.token_expires_at,
        last_refresh_at: connection.last_refresh_at,
        last_refresh_status: dump_optional_atom(connection.last_refresh_status),
        last_rotated_at: connection.last_rotated_at,
        degraded_reason: connection.degraded_reason,
        reauth_required_reason: connection.reauth_required_reason,
        disabled_reason: connection.disabled_reason,
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
           :profile_id,
           :subject,
           :state,
           :credential_ref_id,
           :current_credential_ref_id,
           :current_credential_id,
           :install_id,
           :management_mode,
           :secret_source,
           :external_secret_ref,
           :requested_scopes,
           :granted_scopes,
           :lease_fields,
           :token_expires_at,
           :last_refresh_at,
           :last_refresh_status,
           :last_rotated_at,
           :degraded_reason,
           :reauth_required_reason,
           :disabled_reason,
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
        {:ok, to_contract(record)}
    end
  end

  @impl true
  def list_connections(filters \\ %{}) do
    from(connection in ConnectionRecord,
      order_by: [asc: connection.inserted_at, asc: connection.connection_id]
    )
    |> Repo.all()
    |> Enum.map(&to_contract/1)
    |> filter_records(filters)
  end

  def reset! do
    Repo.delete_all(ConnectionRecord)
    :ok
  end

  defp filter_records(records, filters) when is_map(filters) do
    Enum.filter(records, fn record ->
      Enum.all?(filters, fn {key, value} -> Map.get(record, key) == value end)
    end)
  end

  defp to_contract(record) do
    Connection.new!(%{
      connection_id: record.connection_id,
      tenant_id: record.tenant_id,
      connector_id: record.connector_id,
      auth_type: String.to_existing_atom(record.auth_type),
      profile_id: record.profile_id,
      subject: record.subject,
      state: String.to_existing_atom(record.state),
      credential_ref_id: record.credential_ref_id,
      current_credential_ref_id: record.current_credential_ref_id,
      current_credential_id: record.current_credential_id,
      install_id: record.install_id,
      management_mode: load_optional_atom(record.management_mode),
      secret_source: load_optional_atom(record.secret_source),
      external_secret_ref: load_optional_map(record.external_secret_ref),
      requested_scopes: record.requested_scopes || [],
      granted_scopes: record.granted_scopes || [],
      lease_fields: record.lease_fields || [],
      token_expires_at: record.token_expires_at,
      last_refresh_at: record.last_refresh_at,
      last_refresh_status: load_optional_atom(record.last_refresh_status),
      last_rotated_at: record.last_rotated_at,
      degraded_reason: record.degraded_reason,
      reauth_required_reason: record.reauth_required_reason,
      disabled_reason: record.disabled_reason,
      revoked_at: record.revoked_at,
      revocation_reason: record.revocation_reason,
      actor_id: record.actor_id,
      metadata: Serialization.load(record.metadata || %{}),
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    })
  end

  defp dump_optional_atom(nil), do: nil
  defp dump_optional_atom(value) when is_atom(value), do: Atom.to_string(value)

  defp dump_optional_map(nil), do: nil
  defp dump_optional_map(value), do: Serialization.dump(value)

  defp load_optional_atom(nil), do: nil
  defp load_optional_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp load_optional_map(nil), do: nil
  defp load_optional_map(value), do: Serialization.load(value)
end
