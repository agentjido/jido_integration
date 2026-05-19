defmodule Jido.Integration.V2.Auth.RefreshService do
  @moduledoc """
  Lease issuance, refresh, and external secret hydration service.
  """

  alias Jido.Integration.V2.Auth.ServiceCore

  defdelegate request_lease(connection_id, context \\ %{}), to: ServiceCore
  defdelegate fetch_lease(lease_id, context \\ %{}), to: ServiceCore
  defdelegate renew_lease(lease_id, attrs), to: ServiceCore
  defdelegate set_refresh_handler(handler), to: ServiceCore
  defdelegate set_external_secret_resolver(handler), to: ServiceCore
end
