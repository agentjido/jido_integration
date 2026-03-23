defmodule Jido.Integration.V2.StoreLocal.ConnectionStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.ConnectionStore

  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage

  @impl true
  def store_connection(%Connection{} = connection) do
    Storage.mutate(&State.store_connection(&1, connection))
  end

  @impl true
  def fetch_connection(connection_id) do
    Storage.read(&State.fetch_connection(&1, connection_id))
  end

  @impl true
  def list_connections(filters \\ %{}) do
    Storage.read(&State.list_connections(&1, filters))
  end

  def reset! do
    Storage.mutate(&State.reset_connections/1)
  end
end
