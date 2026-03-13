defmodule Jido.Integration.V2.StorePostgres.InstallStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.InstallStore

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
        subject: install.subject,
        state: Atom.to_string(install.state),
        callback_token: install.callback_token,
        requested_scopes: install.requested_scopes,
        granted_scopes: install.granted_scopes,
        expires_at: install.expires_at,
        completed_at: install.completed_at,
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
           :subject,
           :state,
           :callback_token,
           :requested_scopes,
           :granted_scopes,
           :expires_at,
           :completed_at,
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
        {:ok,
         Install.new!(%{
           install_id: record.install_id,
           connection_id: record.connection_id,
           tenant_id: record.tenant_id,
           connector_id: record.connector_id,
           actor_id: record.actor_id,
           auth_type: String.to_existing_atom(record.auth_type),
           subject: record.subject,
           state: String.to_existing_atom(record.state),
           callback_token: record.callback_token,
           requested_scopes: record.requested_scopes || [],
           granted_scopes: record.granted_scopes || [],
           expires_at: record.expires_at,
           completed_at: record.completed_at,
           metadata: Serialization.load(record.metadata || %{}),
           inserted_at: record.inserted_at,
           updated_at: record.updated_at
         })}
    end
  end

  def reset! do
    Repo.delete_all(InstallRecord)
    :ok
  end
end
