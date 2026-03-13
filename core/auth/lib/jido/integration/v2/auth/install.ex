defmodule Jido.Integration.V2.Auth.Install do
  @moduledoc """
  Durable install-session truth owned by `auth`.
  """

  alias Jido.Integration.V2.Contracts

  @states [:installing, :completed, :expired, :cancelled]

  @enforce_keys [
    :install_id,
    :connection_id,
    :tenant_id,
    :connector_id,
    :actor_id,
    :auth_type,
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
    :subject,
    :state,
    :callback_token,
    :expires_at,
    :completed_at,
    :inserted_at,
    :updated_at,
    requested_scopes: [],
    granted_scopes: [],
    metadata: %{}
  ]

  @type state :: :installing | :completed | :expired | :cancelled

  @type t :: %__MODULE__{
          install_id: String.t(),
          connection_id: String.t(),
          tenant_id: String.t(),
          connector_id: String.t(),
          actor_id: String.t(),
          auth_type: atom(),
          subject: String.t(),
          state: state(),
          callback_token: String.t(),
          requested_scopes: [String.t()],
          granted_scopes: [String.t()],
          expires_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
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
      subject: Map.fetch!(attrs, :subject),
      state: validate_state!(Map.fetch!(attrs, :state)),
      callback_token: Map.fetch!(attrs, :callback_token),
      requested_scopes: Map.get(attrs, :requested_scopes, []),
      granted_scopes: Map.get(attrs, :granted_scopes, []),
      expires_at: Map.fetch!(attrs, :expires_at),
      completed_at: Map.get(attrs, :completed_at),
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
