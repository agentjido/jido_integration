defmodule Jido.Integration.V2.StoreLocal.InstallStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.InstallStore

  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage

  @impl true
  def store_install(%Install{} = install) do
    Storage.mutate(&State.store_install(&1, install))
  end

  @impl true
  def fetch_install(install_id) do
    Storage.read(&State.fetch_install(&1, install_id))
  end

  @impl true
  def list_installs(filters \\ %{}) do
    Storage.read(&State.list_installs(&1, filters))
  end

  def reset! do
    Storage.mutate(&State.reset_installs/1)
  end
end
