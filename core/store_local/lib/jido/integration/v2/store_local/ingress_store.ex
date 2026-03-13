defmodule Jido.Integration.V2.StoreLocal.IngressStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.IngressStore

  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  @impl true
  def transaction(fun) when is_function(fun, 0) do
    Storage.transaction(fun)
  end

  @impl true
  def rollback(reason) do
    Storage.rollback(reason)
  end

  @impl true
  def reserve_dedupe(tenant_id, connector_id, trigger_id, dedupe_key, expires_at) do
    Storage.mutate(
      &State.reserve_dedupe(&1, tenant_id, connector_id, trigger_id, dedupe_key, expires_at)
    )
  end

  @impl true
  def put_trigger(%TriggerRecord{} = trigger) do
    Storage.mutate(&State.put_trigger(&1, trigger))
  end

  @impl true
  def fetch_trigger(tenant_id, connector_id, trigger_id, dedupe_key) do
    Storage.read(&State.fetch_trigger(&1, tenant_id, connector_id, trigger_id, dedupe_key))
  end

  @impl true
  def list_run_triggers(run_id) do
    Storage.read(&State.list_run_triggers(&1, run_id))
  end

  @impl true
  def put_checkpoint(%TriggerCheckpoint{} = checkpoint) do
    Storage.mutate(&State.put_checkpoint(&1, checkpoint))
  end

  @impl true
  def fetch_checkpoint(tenant_id, connector_id, trigger_id, partition_key) do
    Storage.read(&State.fetch_checkpoint(&1, tenant_id, connector_id, trigger_id, partition_key))
  end

  def reset! do
    Storage.mutate(&State.reset_ingress/1)
  end
end
