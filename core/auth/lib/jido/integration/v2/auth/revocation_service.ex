defmodule Jido.Integration.V2.Auth.RevocationService do
  @moduledoc """
  Install, connection, and lease revocation service.
  """

  alias Jido.Integration.V2.Auth.ServiceCore

  defdelegate cancel_install(install_id, attrs \\ %{}), to: ServiceCore
  defdelegate expire_install(install_id, attrs \\ %{}), to: ServiceCore
  defdelegate fail_install(install_id, attrs \\ %{}), to: ServiceCore
  defdelegate revoke_connection(connection_id, attrs), to: ServiceCore
  defdelegate revoke_lease(lease_id, attrs), to: ServiceCore
  defdelegate cleanup_lease(lease_id, attrs), to: ServiceCore
end
