defmodule Jido.Integration.V2.Auth.Install do
  @moduledoc """
  Durable install-session truth owned by `auth`.
  """

  alias Jido.Integration.V2.Contracts

  @states [:installing, :awaiting_callback, :completed, :expired, :cancelled, :failed]

  @enforce_keys [
    :install_id,
    :connection_id,
    :tenant_id,
    :connector_id,
    :actor_id,
    :auth_type,
    :profile_id,
    :subject,
    :state,
    :callback_token,
    :expires_at
  ]
  defstruct [
    :install_id,
    :connection_id,
    :tenant_id,
    :connector_id,
    :actor_id,
    :auth_type,
    :profile_id,
    :subject,
    :state,
    :flow_kind,
    :callback_token,
    :state_token,
    :pkce_verifier_digest,
    :callback_uri,
    :expires_at,
    :callback_received_at,
    :completed_at,
    :cancelled_at,
    :failure_reason,
    :reauth_of_connection_id,
    :inserted_at,
    :updated_at,
    requested_scopes: [],
    granted_scopes: [],
    metadata: %{}
  ]

  @type state :: :installing | :awaiting_callback | :completed | :expired | :cancelled | :failed

  @type t :: %__MODULE__{
          install_id: String.t(),
          connection_id: String.t(),
          tenant_id: String.t(),
          connector_id: String.t(),
          actor_id: String.t(),
          auth_type: atom(),
          profile_id: String.t(),
          subject: String.t(),
          state: state(),
          flow_kind: atom() | nil,
          callback_token: String.t(),
          state_token: String.t() | nil,
          pkce_verifier_digest: String.t() | nil,
          callback_uri: String.t() | nil,
          requested_scopes: [String.t()],
          granted_scopes: [String.t()],
          expires_at: DateTime.t(),
          callback_received_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          cancelled_at: DateTime.t() | nil,
          failure_reason: String.t() | nil,
          reauth_of_connection_id: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    timestamp = Map.get(attrs, :inserted_at, Contracts.now())

    struct!(__MODULE__, %{
      install_id: Map.fetch!(attrs, :install_id),
      connection_id: Map.fetch!(attrs, :connection_id),
      tenant_id: Map.fetch!(attrs, :tenant_id),
      connector_id: Map.fetch!(attrs, :connector_id),
      actor_id: Map.fetch!(attrs, :actor_id),
      auth_type: Map.fetch!(attrs, :auth_type),
      profile_id: Map.fetch!(attrs, :profile_id),
      subject: Map.fetch!(attrs, :subject),
      state: validate_state!(Map.fetch!(attrs, :state)),
      flow_kind: Map.get(attrs, :flow_kind),
      callback_token: Map.fetch!(attrs, :callback_token),
      state_token: Map.get(attrs, :state_token),
      pkce_verifier_digest: Map.get(attrs, :pkce_verifier_digest),
      callback_uri: Map.get(attrs, :callback_uri),
      requested_scopes: Map.get(attrs, :requested_scopes, []),
      granted_scopes: Map.get(attrs, :granted_scopes, []),
      expires_at: Map.fetch!(attrs, :expires_at),
      callback_received_at: Map.get(attrs, :callback_received_at),
      completed_at: Map.get(attrs, :completed_at),
      cancelled_at: Map.get(attrs, :cancelled_at),
      failure_reason: Map.get(attrs, :failure_reason),
      reauth_of_connection_id: Map.get(attrs, :reauth_of_connection_id),
      metadata: Map.get(attrs, :metadata, %{}),
      inserted_at: timestamp,
      updated_at: Map.get(attrs, :updated_at, timestamp)
    })
  end

  @spec validate_state!(state()) :: state()
  def validate_state!(state) when state in @states, do: state

  def validate_state!(state) do
    raise ArgumentError, "invalid auth install state: #{inspect(state)}"
  end

  @spec expired?(t(), DateTime.t()) :: boolean()
  def expired?(%__MODULE__{expires_at: %DateTime{} = expires_at}, %DateTime{} = now) do
    DateTime.compare(expires_at, now) != :gt
  end
end
