defmodule Jido.Integration.V2.ControlPlane.TargetService do
  @moduledoc """
  Runtime target registry and compatibility service behind the control-plane facade.
  """

  alias Jido.Integration.V2.ControlPlane.ServiceCore

  defdelegate announce_target(target_descriptor), to: ServiceCore
  defdelegate fetch_target(target_id), to: ServiceCore
  defdelegate targets(filters \\ %{}), to: ServiceCore
  defdelegate compatible_targets(requirements), to: ServiceCore
end
