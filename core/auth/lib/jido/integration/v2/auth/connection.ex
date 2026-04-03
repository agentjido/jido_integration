defmodule Jido.Integration.V2.Auth.Connection do
  @moduledoc """
  Durable connection truth owned by `auth`.
  """

  alias Jido.Integration.V2.Contracts

  @states [:installing, :connected, :degraded, :reauth_required, :revoked, :disabled]
  @blocked_states [:reauth_required, :revoked, :disabled]
  @allowed_transitions %{
    installing: [:connected, :reauth_required, :revoked, :disabled],
    connected: [:installing, :degraded, :reauth_required, :revoked, :disabled],
    degraded: [:connected, :reauth_required, :revoked, :disabled],
    reauth_required: [:installing, :revoked, :disabled],
    revoked: [:installing, :disabled],
    disabled: [:installing]
  }

  @enforce_keys [:connection_id, :tenant_id, :connector_id, :auth_type, :subject, :state]
  defstruct [
    :connection_id,
    :tenant_id,
    :connector_id,
    :auth_type,
    :profile_id,
    :subject,
    :state,
    :credential_ref_id,
    :current_credential_ref_id,
    :current_credential_id,
    :install_id,
    :management_mode,
    :secret_source,
    :external_secret_ref,
    :token_expires_at,
    :last_refresh_at,
    :last_refresh_status,
    :last_rotated_at,
    :degraded_reason,
    :reauth_required_reason,
    :disabled_reason,
    :revoked_at,
    :revocation_reason,
    :actor_id,
    :inserted_at,
    :updated_at,
    requested_scopes: [],
    granted_scopes: [],
    lease_fields: [],
    metadata: %{}
  ]

  @type state :: :installing | :connected | :degraded | :reauth_required | :revoked | :disabled

  @type t :: %__MODULE__{
          connection_id: String.t(),
          tenant_id: String.t(),
          connector_id: String.t(),
          auth_type: atom(),
          profile_id: String.t() | nil,
          subject: String.t(),
          state: state(),
          credential_ref_id: String.t() | nil,
          current_credential_ref_id: String.t() | nil,
          current_credential_id: String.t() | nil,
          install_id: String.t() | nil,
          management_mode: atom() | nil,
          secret_source: atom() | nil,
          external_secret_ref: map() | nil,
          requested_scopes: [String.t()],
          granted_scopes: [String.t()],
          lease_fields: [String.t()],
          token_expires_at: DateTime.t() | nil,
          last_refresh_at: DateTime.t() | nil,
          last_refresh_status: atom() | nil,
          last_rotated_at: DateTime.t() | nil,
          degraded_reason: String.t() | nil,
          reauth_required_reason: String.t() | nil,
          disabled_reason: String.t() | nil,
          revoked_at: DateTime.t() | nil,
          revocation_reason: String.t() | nil,
          actor_id: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    timestamp = Map.get(attrs, :inserted_at, Contracts.now())

    struct!(__MODULE__, %{
      connection_id: Map.fetch!(attrs, :connection_id),
      tenant_id: Map.fetch!(attrs, :tenant_id),
      connector_id: Map.fetch!(attrs, :connector_id),
      auth_type: Map.fetch!(attrs, :auth_type),
      profile_id: Map.get(attrs, :profile_id),
      subject: Map.fetch!(attrs, :subject),
      state: validate_state!(Map.fetch!(attrs, :state)),
      credential_ref_id: Map.get(attrs, :credential_ref_id),
      current_credential_ref_id:
        Map.get(attrs, :current_credential_ref_id, Map.get(attrs, :credential_ref_id)),
      current_credential_id: Map.get(attrs, :current_credential_id),
      install_id: Map.get(attrs, :install_id),
      management_mode: Map.get(attrs, :management_mode),
      secret_source: Map.get(attrs, :secret_source),
      external_secret_ref: Map.get(attrs, :external_secret_ref),
      requested_scopes: Map.get(attrs, :requested_scopes, []),
      granted_scopes: Map.get(attrs, :granted_scopes, []),
      lease_fields: Map.get(attrs, :lease_fields, []),
      token_expires_at: Map.get(attrs, :token_expires_at),
      last_refresh_at: Map.get(attrs, :last_refresh_at),
      last_refresh_status: Map.get(attrs, :last_refresh_status),
      last_rotated_at: Map.get(attrs, :last_rotated_at),
      degraded_reason: Map.get(attrs, :degraded_reason),
      reauth_required_reason: Map.get(attrs, :reauth_required_reason),
      disabled_reason: Map.get(attrs, :disabled_reason),
      revoked_at: Map.get(attrs, :revoked_at),
      revocation_reason: Map.get(attrs, :revocation_reason),
      actor_id: Map.get(attrs, :actor_id),
      metadata: Map.get(attrs, :metadata, %{}),
      inserted_at: timestamp,
      updated_at: Map.get(attrs, :updated_at, timestamp)
    })
  end

  @spec validate_state!(state()) :: state()
  def validate_state!(state) when state in @states, do: state

  def validate_state!(state) do
    raise ArgumentError, "invalid auth connection state: #{inspect(state)}"
  end

  @spec blocked?(t()) :: boolean()
  def blocked?(%__MODULE__{state: state}), do: state in @blocked_states

  @spec can_transition?(state(), state()) :: boolean()
  def can_transition?(from, to) do
    to in Map.get(@allowed_transitions, from, [])
  end
end
