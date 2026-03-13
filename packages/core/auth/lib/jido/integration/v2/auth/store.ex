defmodule Jido.Integration.V2.Auth.Store do
  @moduledoc false

  use Agent

  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.Auth.LeaseRecord
  alias Jido.Integration.V2.Credential

  @behaviour Jido.Integration.V2.Auth.CredentialStore
  @behaviour Jido.Integration.V2.Auth.LeaseStore
  @behaviour Jido.Integration.V2.Auth.ConnectionStore
  @behaviour Jido.Integration.V2.Auth.InstallStore

  def start_link(_opts) do
    Agent.start_link(
      fn ->
        %{
          credentials: %{},
          leases: %{},
          connections: %{},
          installs: %{},
          refresh_handler: nil
        }
      end,
      name: __MODULE__
    )
  end

  @impl Jido.Integration.V2.Auth.CredentialStore
  def store_credential(%Credential{} = credential) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:credentials, credential.id], credential)
    end)
  end

  @impl Jido.Integration.V2.Auth.CredentialStore
  def fetch_credential(id) do
    Agent.get(__MODULE__, fn state ->
      case get_in(state, [:credentials, id]) do
        %Credential{} = credential -> {:ok, credential}
        nil -> {:error, :unknown_credential}
      end
    end)
  end

  @impl Jido.Integration.V2.Auth.LeaseStore
  def store_lease(%LeaseRecord{} = lease) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:leases, lease.lease_id], lease)
    end)
  end

  @impl Jido.Integration.V2.Auth.LeaseStore
  def fetch_lease(id) do
    Agent.get(__MODULE__, fn state ->
      case get_in(state, [:leases, id]) do
        %LeaseRecord{} = lease -> {:ok, lease}
        nil -> {:error, :unknown_lease}
      end
    end)
  end

  @impl Jido.Integration.V2.Auth.ConnectionStore
  def store_connection(%Connection{} = connection) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:connections, connection.connection_id], connection)
    end)
  end

  @impl Jido.Integration.V2.Auth.ConnectionStore
  def fetch_connection(connection_id) do
    Agent.get(__MODULE__, fn state ->
      case get_in(state, [:connections, connection_id]) do
        %Connection{} = connection -> {:ok, connection}
        nil -> {:error, :unknown_connection}
      end
    end)
  end

  @impl Jido.Integration.V2.Auth.InstallStore
  def store_install(%Install{} = install) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:installs, install.install_id], install)
    end)
  end

  @impl Jido.Integration.V2.Auth.InstallStore
  def fetch_install(install_id) do
    Agent.get(__MODULE__, fn state ->
      case get_in(state, [:installs, install_id]) do
        %Install{} = install -> {:ok, install}
        nil -> {:error, :unknown_install}
      end
    end)
  end

  def set_refresh_handler(handler) when is_function(handler, 2) or is_nil(handler) do
    Agent.update(__MODULE__, &Map.put(&1, :refresh_handler, handler))
  end

  def refresh_handler do
    Agent.get(__MODULE__, &Map.get(&1, :refresh_handler))
  end

  def put(%Credential{} = credential), do: store_credential(credential)
  def fetch(id), do: fetch_credential(id)

  def reset! do
    Agent.update(__MODULE__, fn _ ->
      %{credentials: %{}, leases: %{}, connections: %{}, installs: %{}, refresh_handler: nil}
    end)
  end
end
