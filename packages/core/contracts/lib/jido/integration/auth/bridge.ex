defmodule Jido.Integration.Auth.Bridge do
  @moduledoc """
  Auth bridge behaviour — the host integration boundary around the
  runtime-owned auth engine.

  `Jido.Integration.Auth.Server` is the canonical auth lifecycle engine in the
  substrate. It owns install state transitions, callback validation,
  credential and connection state, refresh coordination, and scope gating.

  Host frameworks such as Phoenix or Ash implement this behaviour to expose
  that engine through their own HTTP, tenancy, secret-backend, and admin
  surfaces. A bridge implementation typically:

  - routes install and callback requests into the correct `Auth.Server`
  - maps host request state into `tenant_id`, `actor_id`, and connection context
  - selects the runtime instance and backing store/vault adapters
  - exposes host-facing APIs for connection health and revocation

  The bridge does not redefine lifecycle truth. Host apps should not
  reimplement install-session validation, callback anti-replay rules, refresh
  coordination, or scope gating semantics in parallel with `Auth.Server`.

  Install and callback correlation is backed by a durable install-session
  record managed by `Auth.Server`. The host-visible `session_state` payload is
  only the opaque callback handle the bridge must round-trip through its HTTP
  boundary.

  The callback shapes below intentionally mirror the runtime responses from
  `Auth.Server.start_install/4` and `Auth.Server.handle_callback/4`.

  ## Callbacks

  - `start_install/3` — begin an install by delegating to `Auth.Server`
  - `handle_callback/3` — forward callback data into `Auth.Server`
  - `get_token/1` — return an opaque handle for a runtime-managed connection
  - `revoke/2` — request revocation for a runtime-managed connection
  - `connection_health/1` — expose runtime connection health through the host
  - `check_scopes/2` — expose runtime scope gates to host APIs

  ## Example Implementation

      defmodule MyApp.AuthBridge do
        @behaviour Jido.Integration.Auth.Bridge

        alias Jido.Integration.Auth.Server

        @impl true
        def start_install(connector_id, tenant_id, opts) do
          Server.start_install(auth_server_for(opts), connector_id, tenant_id, opts)
        end

        @impl true
        def get_token(connection_id) do
          with {:ok, connection} <- Server.get_connection(auth_server_for([]), connection_id) do
            {:ok,
             %{
               auth_ref: connection.auth_ref,
               token_ref: connection.auth_ref,
               expires_at: nil
             }}
          end
        end

        defp auth_server_for(_opts), do: MyApp.IntegrationRuntime.auth_server()
      end
  """

  @typedoc "Connector manifest ID."
  @type connector_id :: String.t()

  @typedoc "Tenant or installation owner resolved by the host."
  @type tenant_id :: String.t()

  @typedoc "Runtime-managed connection identifier."
  @type connection_id :: String.t()

  @typedoc "Opaque auth reference issued by `Auth.Server`."
  @type auth_ref :: String.t()

  @typedoc """
  Serialized install session data issued by `Auth.Server.start_install/4`.

  This is an opaque host payload that points back to a durable install-session
  record owned by `Auth.Server`.
  """
  @type session_state :: map()

  @typedoc "Host-supplied install options forwarded to the runtime."
  @type install_opts :: map()

  @typedoc """
  Host-facing result for an install start request.

  This mirrors the runtime response and keeps `connection_id` visible to the
  host boundary without asking the host to create its own lifecycle record.
  """
  @type install_result :: %{
          required(:auth_url) => String.t(),
          required(:session_state) => session_state(),
          required(:connection_id) => connection_id()
        }

  @typedoc "Callback params received from the host framework."
  @type callback_params :: map()

  @typedoc """
  Host-facing result for a completed callback.

  `auth_ref` is the canonical credential handle issued by `Auth.Server`.
  """
  @type callback_result :: %{
          required(:connection_id) => connection_id(),
          required(:state) => atom(),
          required(:auth_ref) => auth_ref()
        }

  @typedoc """
  Opaque credential metadata for a runtime-managed connection.

  `token_ref` may be the same value as `auth_ref` or a host-specific vault
  reference derived from it. The bridge should not create a second lifecycle
  source of truth here.
  """
  @type token_result :: %{
          required(:auth_ref) => auth_ref(),
          optional(:token_ref) => String.t() | nil,
          optional(:expires_at) => DateTime.t() | nil
        }

  @doc """
  Initiate an auth install flow through the runtime-owned `Auth.Server`.

  Host code is expected to forward actor, tenant, and request context in `opts`
  before delegating into the runtime.
  """
  @callback start_install(
              connector_id :: connector_id(),
              tenant_id :: tenant_id(),
              opts :: install_opts()
            ) ::
              {:ok, install_result()}
              | {:error, term()}

  @doc """
  Handle a provider callback by forwarding it into `Auth.Server`.

  The host owns HTTP routing and request parsing. `Auth.Server` remains the
  owner of callback validation, anti-replay, credential persistence, and the
  final connection transition.
  """
  @callback handle_callback(
              connector_id :: connector_id(),
              params :: callback_params(),
              session_state :: session_state()
            ) ::
              {:ok, callback_result()}
              | {:error, term()}

  @doc """
  Return an opaque credential handle for a runtime-managed connection.

  This is a host-facing read model around `Auth.Server`, not a second token
  lifecycle implementation.
  """
  @callback get_token(connection_id :: connection_id()) ::
              {:ok, token_result()}
              | {:error, term()}

  @doc "Request revocation for a runtime-managed connection."
  @callback revoke(connection_id :: connection_id(), reason :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Expose runtime connection health through the host boundary.
  """
  @callback connection_health(connection_id :: connection_id()) ::
              {:ok, %{status: atom(), details: map()}}
              | {:error, term()}

  @doc """
  Verify that required scopes are available for a runtime-managed connection.
  """
  @callback check_scopes(connection_id :: connection_id(), required_scopes :: [String.t()]) ::
              :ok | {:error, %{missing_scopes: [String.t()]}}
end
