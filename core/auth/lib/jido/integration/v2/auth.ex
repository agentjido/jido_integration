defmodule Jido.Integration.V2.Auth do
  @moduledoc """
  Public auth facade for durable installs, credentials, leases, assertions,
  refresh, and revocation.
  """

  alias Jido.Integration.V2.Auth.AssertionService
  alias Jido.Integration.V2.Auth.CallbackService
  alias Jido.Integration.V2.Auth.CredentialService
  alias Jido.Integration.V2.Auth.InstallService
  alias Jido.Integration.V2.Auth.RefreshService
  alias Jido.Integration.V2.Auth.RevocationService
  alias Jido.Integration.V2.Auth.ServiceCore
  alias Jido.Integration.V2.Auth.StoreConfig

  @type refresh_handler :: ServiceCore.refresh_handler()
  @type external_secret_stage :: ServiceCore.external_secret_stage()
  @type external_secret_opts :: ServiceCore.external_secret_opts()
  @type external_secret_resolver :: ServiceCore.external_secret_resolver()
  @type connection_binding :: ServiceCore.connection_binding()

  defdelegate start_install(connector_id, tenant_id, opts \\ %{}), to: InstallService
  defdelegate complete_install(install_id, attrs), to: InstallService
  defdelegate fetch_install(install_id), to: InstallService
  defdelegate installs(filters \\ %{}), to: InstallService
  defdelegate reauthorize_connection(connection_id, opts \\ %{}), to: InstallService

  defdelegate resolve_install_callback(attrs), to: CallbackService

  defdelegate connection_status(connection_id), to: CredentialService
  defdelegate connections(filters \\ %{}), to: CredentialService
  defdelegate resolve_connection_binding(connection_id, context \\ %{}), to: CredentialService
  defdelegate issue_lease(credential_ref, context \\ %{}), to: CredentialService
  defdelegate resolve(credential_ref, context \\ %{}), to: CredentialService
  defdelegate resolve_secret(credential_ref, secret_key), to: CredentialService
  defdelegate rotate_connection(connection_id, attrs), to: CredentialService

  defdelegate request_lease(connection_id, context \\ %{}), to: RefreshService
  defdelegate fetch_lease(lease_id, context \\ %{}), to: RefreshService
  defdelegate renew_lease(lease_id, attrs), to: RefreshService
  defdelegate set_refresh_handler(handler), to: RefreshService
  defdelegate set_external_secret_resolver(handler), to: RefreshService

  defdelegate request_governed_lease(connection_id, context), to: AssertionService
  defdelegate redeem_lease(lease_id, context), to: AssertionService
  defdelegate lease_audit_event(event_name, lease), to: AssertionService
  defdelegate lease_fence_event(lease), to: AssertionService

  defdelegate cancel_install(install_id, attrs \\ %{}), to: RevocationService
  defdelegate expire_install(install_id, attrs \\ %{}), to: RevocationService
  defdelegate fail_install(install_id, attrs \\ %{}), to: RevocationService
  defdelegate revoke_connection(connection_id, attrs), to: RevocationService
  defdelegate revoke_lease(lease_id, attrs), to: RevocationService
  defdelegate cleanup_lease(lease_id, attrs), to: RevocationService

  defdelegate reset!(), to: StoreConfig
end
