defmodule Jido.Integration.V2.StoreLocal.LeaseStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.LeaseStore

  alias Jido.Integration.V2.Auth.LeaseRecord
  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage

  @impl true
  def store_lease(%LeaseRecord{} = lease) do
    Storage.mutate(&State.store_lease(&1, lease))
  end

  @impl true
  def fetch_lease(lease_id) do
    Storage.read(&State.fetch_lease(&1, lease_id))
  end

  def reset! do
    Storage.mutate(&State.reset_leases/1)
  end
end
