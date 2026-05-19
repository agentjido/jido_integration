defmodule Jido.Integration.V2.ControlPlane.Stores do
  @moduledoc false

  alias Jido.Integration.V2.ControlPlane.Persistence

  @spec run_store() :: module()
  def run_store do
    configured_store(:run_store)
  end

  @spec attempt_store() :: module()
  def attempt_store do
    configured_store(:attempt_store)
  end

  @spec event_store() :: module()
  def event_store do
    configured_store(:event_store)
  end

  @spec artifact_store() :: module()
  def artifact_store do
    configured_store(:artifact_store)
  end

  @spec claim_check_store() :: module()
  def claim_check_store do
    configured_store(:claim_check_store)
  end

  @spec target_store() :: module()
  def target_store do
    configured_store(:target_store)
  end

  @spec ingress_store() :: module()
  def ingress_store do
    configured_store(:ingress_store)
  end

  @spec profile_registry_store() :: module()
  def profile_registry_store do
    configured_store(:profile_registry_store)
  end

  defp configured_store(key) do
    Persistence.store_module(key)
  end
end
