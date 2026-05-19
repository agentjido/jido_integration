defmodule Jido.Integration.V2.Auth.AssertionService do
  @moduledoc """
  Governed lease assertion, redemption, audit, and fence service.
  """

  alias Jido.Integration.V2.Auth.ServiceCore

  defdelegate request_governed_lease(connection_id, context), to: ServiceCore
  defdelegate redeem_lease(lease_id, context), to: ServiceCore
  defdelegate lease_audit_event(event_name, lease), to: ServiceCore
  defdelegate lease_fence_event(lease), to: ServiceCore
end
