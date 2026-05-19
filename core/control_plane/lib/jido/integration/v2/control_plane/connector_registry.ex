defmodule Jido.Integration.V2.ControlPlane.ConnectorRegistry do
  @moduledoc """
  Connector manifest and capability registry service behind the control-plane facade.
  """

  alias Jido.Integration.V2.ControlPlane.ServiceCore

  defdelegate register_connector(connector), to: ServiceCore
  defdelegate connectors(), to: ServiceCore
  defdelegate fetch_connector(connector_id), to: ServiceCore
  defdelegate capabilities(), to: ServiceCore
  defdelegate fetch_capability(capability_id), to: ServiceCore
end
