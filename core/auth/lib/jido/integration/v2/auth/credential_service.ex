defmodule Jido.Integration.V2.Auth.CredentialService do
  @moduledoc """
  Credential binding, rotation, and secret-resolution service.
  """

  alias Jido.Integration.V2.Auth.ServiceCore

  defdelegate connection_status(connection_id), to: ServiceCore
  defdelegate connections(filters \\ %{}), to: ServiceCore
  defdelegate resolve_connection_binding(connection_id, context \\ %{}), to: ServiceCore
  defdelegate issue_lease(credential_ref, context \\ %{}), to: ServiceCore
  defdelegate resolve(credential_ref, context \\ %{}), to: ServiceCore
  defdelegate resolve_secret(credential_ref, secret_key), to: ServiceCore
  defdelegate rotate_connection(connection_id, attrs), to: ServiceCore
end
