defmodule Jido.Integration.V2.ControlPlane.SimulationProfileService do
  @moduledoc """
  Simulation profile registry service behind the control-plane facade.
  """

  alias Jido.Integration.V2.ControlPlane.ServiceCore

  defdelegate install_simulation_profile(profile, installed_scenarios, attrs \\ %{}),
    to: ServiceCore

  defdelegate update_simulation_profile(profile, installed_scenarios, attrs \\ %{}),
    to: ServiceCore

  defdelegate remove_simulation_profile(profile_id, attrs \\ %{}), to: ServiceCore
  defdelegate fetch_simulation_profile(profile_id), to: ServiceCore
  defdelegate select_simulation_profile(profile_id, environment_scope, owner_ref), to: ServiceCore
  defdelegate simulation_profiles(filters \\ %{}), to: ServiceCore
end
