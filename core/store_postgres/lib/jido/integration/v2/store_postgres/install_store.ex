defmodule Jido.Integration.V2.StorePostgres.InstallStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.InstallStore

  import Ecto.Query

  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.InstallRecord
  alias Jido.Integration.V2.StorePostgres.Serialization

  @impl true
  def store_install(%Install{} = install) do
    attrs =
      %{
        install_id: install.install_id,
        connection_id: install.connection_id,
        tenant_id: install.tenant_id,
        connector_id: install.connector_id,
        actor_id: install.actor_id,
        auth_type: Atom.to_string(install.auth_type),
        profile_id: install.profile_id,
        subject: install.subject,
        state: Atom.to_string(install.state),
        flow_kind: dump_optional_atom(install.flow_kind),
        callback_token: install.callback_token,
        state_token: install.state_token,
        pkce_verifier_digest: install.pkce_verifier_digest,
        callback_uri: install.callback_uri,
        requested_scopes: install.requested_scopes,
        granted_scopes: install.granted_scopes,
        expires_at: install.expires_at,
        callback_received_at: install.callback_received_at,
        completed_at: install.completed_at,
        cancelled_at: install.cancelled_at,
        failure_reason: install.failure_reason,
        reauth_of_connection_id: install.reauth_of_connection_id,
        metadata: Serialization.dump(install.metadata),
        inserted_at: install.inserted_at || Contracts.now(),
        updated_at: install.updated_at || Contracts.now()
      }

    %InstallRecord{}
    |> InstallRecord.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :connection_id,
           :tenant_id,
           :connector_id,
           :actor_id,
           :auth_type,
           :profile_id,
           :subject,
           :state,
           :flow_kind,
           :callback_token,
           :state_token,
           :pkce_verifier_digest,
           :callback_uri,
           :requested_scopes,
           :granted_scopes,
           :expires_at,
           :callback_received_at,
           :completed_at,
           :cancelled_at,
           :failure_reason,
           :reauth_of_connection_id,
           :metadata,
           :updated_at
         ]},
      conflict_target: [:install_id]
    )
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def fetch_install(install_id) do
    case Repo.get(InstallRecord, install_id) do
      nil ->
        {:error, :unknown_install}

      record ->
        {:ok, to_contract(record)}
    end
  end

  @impl true
  def list_installs(filters \\ %{}) do
    from(install in InstallRecord,
      order_by: [asc: install.inserted_at, asc: install.install_id]
    )
    |> Repo.all()
    |> Enum.map(&to_contract/1)
    |> filter_records(filters)
  end

  def reset! do
    Repo.delete_all(InstallRecord)
    :ok
  end

  defp filter_records(records, filters) when is_map(filters) do
    Enum.filter(records, fn record ->
      Enum.all?(filters, fn {key, value} -> Map.get(record, key) == value end)
    end)
  end

  defp to_contract(record) do
    Install.new!(%{
      install_id: record.install_id,
      connection_id: record.connection_id,
      tenant_id: record.tenant_id,
      connector_id: record.connector_id,
      actor_id: record.actor_id,
      auth_type: String.to_existing_atom(record.auth_type),
      profile_id: record.profile_id,
      subject: record.subject,
      state: String.to_existing_atom(record.state),
      flow_kind: load_optional_atom(record.flow_kind),
      callback_token: record.callback_token,
      state_token: record.state_token,
      pkce_verifier_digest: record.pkce_verifier_digest,
      callback_uri: record.callback_uri,
      requested_scopes: record.requested_scopes || [],
      granted_scopes: record.granted_scopes || [],
      expires_at: record.expires_at,
      callback_received_at: record.callback_received_at,
      completed_at: record.completed_at,
      cancelled_at: record.cancelled_at,
      failure_reason: record.failure_reason,
      reauth_of_connection_id: record.reauth_of_connection_id,
      metadata: Serialization.load(record.metadata || %{}),
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    })
  end

  defp dump_optional_atom(nil), do: nil
  defp dump_optional_atom(value) when is_atom(value), do: Atom.to_string(value)

  defp load_optional_atom(nil), do: nil
  defp load_optional_atom(value) when is_binary(value), do: String.to_existing_atom(value)
end
