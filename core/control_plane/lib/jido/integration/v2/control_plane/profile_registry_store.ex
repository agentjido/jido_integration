defmodule Jido.Integration.V2.ControlPlane.ProfileRegistryStore do
  @moduledoc """
  Durable service profile registry truth owned by `control_plane`.
  """

  alias Jido.Integration.V2.ServiceSimulationProfile
  alias Jido.Integration.V2.SimulationProfileRegistryEntry

  @callback install_profile(ServiceSimulationProfile.t() | map() | keyword(), [map()], map()) ::
              {:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()}
  @callback update_profile(ServiceSimulationProfile.t() | map() | keyword(), [map()], map()) ::
              {:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()}
  @callback remove_profile(String.t(), map()) ::
              {:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()}
  @callback fetch_profile(String.t()) :: {:ok, SimulationProfileRegistryEntry.t()} | :error
  @callback select_profile(String.t(), String.t(), String.t()) ::
              {:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()} | :error
  @callback list_profiles(map()) :: [SimulationProfileRegistryEntry.t()]
end
