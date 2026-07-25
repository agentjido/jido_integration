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

  @impl true
  def record_redemption(lease_id, now, max_calls) do
    Storage.mutate(&State.record_lease_redemption(&1, lease_id, now, max_calls))
  end

  @impl true
  def record_materialization(lease_id, materialization_ref, now) do
    Storage.mutate(&State.record_lease_materialization(&1, lease_id, materialization_ref, now))
  end

  def reset! do
    Storage.mutate(&State.reset_leases/1)
  end
end
