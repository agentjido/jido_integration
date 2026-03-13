defmodule Jido.Integration.V2.CredentialLease do
  @moduledoc """
  Short-lived execution material derived from a durable `CredentialRef`.
  """

  alias Jido.Integration.V2.Contracts

  @enforce_keys [
    :lease_id,
    :credential_ref_id,
    :subject,
    :scopes,
    :payload,
    :issued_at,
    :expires_at
  ]
  defstruct [
    :lease_id,
    :credential_ref_id,
    :subject,
    :scopes,
    :payload,
    :issued_at,
    :expires_at,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          lease_id: String.t(),
          credential_ref_id: String.t(),
          subject: String.t(),
          scopes: [String.t()],
          payload: map(),
          issued_at: DateTime.t(),
          expires_at: DateTime.t(),
          metadata: map()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    issued_at = Map.get(attrs, :issued_at, Contracts.now())
    expires_at = Map.fetch!(attrs, :expires_at)

    if DateTime.compare(expires_at, issued_at) != :gt do
      raise ArgumentError,
            "credential lease expires_at must be after issued_at: #{inspect({issued_at, expires_at})}"
    end

    struct!(__MODULE__, %{
      lease_id: Map.fetch!(attrs, :lease_id),
      credential_ref_id: Map.fetch!(attrs, :credential_ref_id),
      subject: Map.fetch!(attrs, :subject),
      scopes: Map.get(attrs, :scopes, []),
      payload: Map.fetch!(attrs, :payload),
      issued_at: issued_at,
      expires_at: expires_at,
      metadata: Map.get(attrs, :metadata, %{})
    })
  end

  @spec expired?(t(), DateTime.t()) :: boolean()
  def expired?(%__MODULE__{expires_at: %DateTime{} = expires_at}, %DateTime{} = now) do
    DateTime.compare(expires_at, now) != :gt
  end
end
