defmodule Jido.Integration.V2.Auth.LeaseRecord do
  @moduledoc """
  Durable lease metadata. Secret payload is reconstructed from credential truth.
  """

  alias Jido.Integration.V2.Contracts

  @enforce_keys [
    :lease_id,
    :credential_ref_id,
    :connection_id,
    :subject,
    :scopes,
    :payload_keys,
    :issued_at,
    :expires_at
  ]
  defstruct [
    :lease_id,
    :credential_ref_id,
    :connection_id,
    :subject,
    :scopes,
    :payload_keys,
    :issued_at,
    :expires_at,
    :revoked_at,
    inserted_at: nil,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          lease_id: String.t(),
          credential_ref_id: String.t(),
          connection_id: String.t(),
          subject: String.t(),
          scopes: [String.t()],
          payload_keys: [String.t()],
          issued_at: DateTime.t(),
          expires_at: DateTime.t(),
          revoked_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          metadata: map()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    issued_at = Map.get(attrs, :issued_at, Contracts.now())
    expires_at = Map.fetch!(attrs, :expires_at)

    if DateTime.compare(expires_at, issued_at) != :gt do
      raise ArgumentError,
            "lease record expires_at must be after issued_at: #{inspect({issued_at, expires_at})}"
    end

    struct!(__MODULE__, %{
      lease_id: Map.fetch!(attrs, :lease_id),
      credential_ref_id: Map.fetch!(attrs, :credential_ref_id),
      connection_id: Map.fetch!(attrs, :connection_id),
      subject: Map.fetch!(attrs, :subject),
      scopes: Map.get(attrs, :scopes, []),
      payload_keys: Map.get(attrs, :payload_keys, []),
      issued_at: issued_at,
      expires_at: expires_at,
      revoked_at: Map.get(attrs, :revoked_at),
      inserted_at: Map.get(attrs, :inserted_at, issued_at),
      metadata: Map.get(attrs, :metadata, %{})
    })
  end
end
