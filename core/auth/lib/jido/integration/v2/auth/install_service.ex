defmodule Jido.Integration.V2.Auth.InstallService do
  @moduledoc """
  Install and reauthorization service behind `Jido.Integration.V2.Auth`.
  """

  alias Jido.Integration.V2.Auth.ServiceCore

  defdelegate start_install(connector_id, tenant_id, opts \\ %{}), to: ServiceCore
  defdelegate complete_install(install_id, attrs), to: ServiceCore
  defdelegate fetch_install(install_id), to: ServiceCore
  defdelegate installs(filters \\ %{}), to: ServiceCore
  defdelegate reauthorize_connection(connection_id, opts \\ %{}), to: ServiceCore
end
