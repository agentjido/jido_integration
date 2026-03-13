defmodule Jido.Integration.Auth.InstallSession do
  @moduledoc """
  Durable install-session record for auth start and callback correlation.
  """

  alias Jido.Integration.Error

  @type status :: :pending | :consumed

  @type t :: %__MODULE__{
          state_token: String.t(),
          connector_id: String.t(),
          tenant_id: String.t(),
          connection_id: String.t(),
          auth_descriptor_id: String.t(),
          auth_type: atom(),
          requested_scopes: [String.t()],
          nonce: String.t(),
          code_challenge: String.t() | nil,
          code_verifier: String.t() | nil,
          code_verifier_ref: String.t() | nil,
          actor_id: String.t() | nil,
          trace_id: String.t() | nil,
          span_id: String.t() | nil,
          status: status(),
          expires_at: DateTime.t(),
          created_at: DateTime.t(),
          consumed_at: DateTime.t() | nil
        }

  @enforce_keys [
    :state_token,
    :connector_id,
    :tenant_id,
    :connection_id,
    :auth_descriptor_id,
    :auth_type,
    :requested_scopes,
    :nonce,
    :expires_at,
    :created_at
  ]
  defstruct [
    :state_token,
    :connector_id,
    :tenant_id,
    :connection_id,
    :auth_descriptor_id,
    :auth_type,
    :requested_scopes,
    :nonce,
    :code_challenge,
    :code_verifier,
    :code_verifier_ref,
    :actor_id,
    :trace_id,
    :span_id,
    :expires_at,
    :created_at,
    :consumed_at,
    status: :pending
  ]

  @required_fields [
    :state_token,
    :connector_id,
    :tenant_id,
    :connection_id,
    :auth_descriptor_id,
    :auth_type,
    :requested_scopes,
    :nonce,
    :expires_at,
    :created_at
  ]

  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_map(attrs) do
    case Enum.find(@required_fields, &(Map.get(attrs, &1) in [nil, ""])) do
      nil ->
        {:ok,
         struct(__MODULE__, %{
           state_token: Map.fetch!(attrs, :state_token),
           connector_id: Map.fetch!(attrs, :connector_id),
           tenant_id: Map.fetch!(attrs, :tenant_id),
           connection_id: Map.fetch!(attrs, :connection_id),
           auth_descriptor_id: Map.fetch!(attrs, :auth_descriptor_id),
           auth_type: Map.fetch!(attrs, :auth_type),
           requested_scopes: Map.fetch!(attrs, :requested_scopes),
           nonce: Map.fetch!(attrs, :nonce),
           code_challenge: Map.get(attrs, :code_challenge),
           code_verifier: Map.get(attrs, :code_verifier),
           code_verifier_ref: Map.get(attrs, :code_verifier_ref),
           actor_id: Map.get(attrs, :actor_id),
           trace_id: Map.get(attrs, :trace_id),
           span_id: Map.get(attrs, :span_id),
           status: Map.get(attrs, :status, :pending),
           expires_at: Map.fetch!(attrs, :expires_at),
           created_at: Map.fetch!(attrs, :created_at),
           consumed_at: Map.get(attrs, :consumed_at)
         })}

      field ->
        {:error, Error.new(:invalid_request, "Install session requires #{field}")}
    end
  end

  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end

  @spec consumed?(t()) :: boolean()
  def consumed?(%__MODULE__{status: :consumed}), do: true
  def consumed?(%__MODULE__{}), do: false

  @spec consume(t(), DateTime.t()) :: t()
  def consume(%__MODULE__{} = session, consumed_at \\ DateTime.utc_now()) do
    %{session | status: :consumed, consumed_at: consumed_at}
  end
end
