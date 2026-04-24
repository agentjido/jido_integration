defmodule Jido.Integration.V2.StoreLocal.ProfileRegistryStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.ProfileRegistryStore

  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage

  @impl true
  def install_profile(profile, installed_scenarios, attrs) do
    Storage.mutate(&State.install_profile_registry_entry(&1, profile, installed_scenarios, attrs))
  end

  @impl true
  def update_profile(profile, installed_scenarios, attrs) do
    Storage.mutate(&State.update_profile_registry_entry(&1, profile, installed_scenarios, attrs))
  end

  @impl true
  def remove_profile(profile_id, attrs) do
    Storage.mutate(&State.remove_profile_registry_entry(&1, profile_id, attrs))
  end

  @impl true
  def fetch_profile(profile_id) do
    Storage.read(&State.fetch_profile_registry_entry(&1, profile_id))
  end

  @impl true
  def select_profile(profile_id, environment_scope, owner_ref) do
    Storage.read(
      &State.select_profile_registry_entry(&1, profile_id, environment_scope, owner_ref)
    )
  end

  @impl true
  def list_profiles(filters \\ %{}) do
    Storage.read(&State.list_profile_registry_entries(&1, filters))
  end

  def reset! do
    Storage.mutate(&State.reset_profile_registry/1)
  end
end
