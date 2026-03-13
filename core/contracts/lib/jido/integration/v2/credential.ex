defmodule Jido.Integration.V2.Credential do
  @moduledoc """
  Resolved credential owned by the control plane.
  """

  alias Jido.Integration.V2.Contracts

  @non_leaseable_secret_keys ~w(refresh_token client_secret webhook_secret private_key password)

  @enforce_keys [:id, :subject, :auth_type]
  defstruct [
    :id,
    :connection_id,
    :subject,
    :auth_type,
    :expires_at,
    :revoked_at,
    scopes: [],
    secret: %{},
    lease_fields: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          connection_id: String.t() | nil,
          subject: String.t(),
          auth_type: atom(),
          scopes: [String.t()],
          secret: map(),
          lease_fields: [String.t()],
          expires_at: DateTime.t() | nil,
          revoked_at: DateTime.t() | nil,
          metadata: map()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    secret = Map.get(attrs, :secret, %{})
    lease_fields = Map.get(attrs, :lease_fields)

    struct!(__MODULE__, %{
      id: Map.fetch!(attrs, :id),
      connection_id: Map.get(attrs, :connection_id),
      subject: Map.fetch!(attrs, :subject),
      auth_type: Map.fetch!(attrs, :auth_type),
      scopes: Map.get(attrs, :scopes, []),
      secret: secret,
      lease_fields:
        normalize_lease_fields(
          if(is_nil(lease_fields), do: default_lease_fields(secret), else: lease_fields)
        ),
      expires_at: Map.get(attrs, :expires_at),
      revoked_at: Map.get(attrs, :revoked_at),
      metadata: Map.get(attrs, :metadata, %{})
    })
  end

  @spec expired?(t(), DateTime.t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}, _now), do: false

  def expired?(%__MODULE__{expires_at: %DateTime{} = expires_at}, %DateTime{} = now) do
    DateTime.compare(expires_at, now) != :gt
  end

  @spec active?(t(), DateTime.t()) :: boolean()
  def active?(%__MODULE__{revoked_at: %DateTime{}}, _now), do: false
  def active?(%__MODULE__{} = credential, %DateTime{} = now), do: not expired?(credential, now)

  @spec lease_payload(t(), [String.t()] | nil) :: map()
  def lease_payload(%__MODULE__{} = credential, requested_fields \\ nil) do
    fields =
      case requested_fields do
        nil -> credential.lease_fields
        list when is_list(list) -> normalize_lease_fields(list)
      end

    Enum.reduce(fields, %{}, fn field, acc ->
      case secret_entry(credential.secret, field) do
        {:ok, key, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  @spec sanitized(t()) :: t()
  def sanitized(%__MODULE__{} = credential) do
    %__MODULE__{credential | secret: %{}}
  end

  @spec now() :: DateTime.t()
  def now, do: Contracts.now()

  defp default_lease_fields(secret) when is_map(secret) do
    secret
    |> Map.keys()
    |> Enum.map(&normalize_secret_key/1)
    |> Enum.reject(&(&1 in @non_leaseable_secret_keys))
  end

  defp normalize_lease_fields(fields) do
    fields
    |> Enum.map(&normalize_secret_key/1)
    |> Enum.uniq()
  end

  defp secret_entry(secret, field) when is_map(secret) do
    case Enum.find(Map.keys(secret), &(normalize_secret_key(&1) == field)) do
      nil -> :error
      key -> {:ok, key, Map.fetch!(secret, key)}
    end
  end

  defp normalize_secret_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_secret_key(key) when is_binary(key), do: key
end
