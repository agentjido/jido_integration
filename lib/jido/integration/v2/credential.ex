defmodule Jido.Integration.V2.Credential do
  @moduledoc """
  Resolved credential owned by the control plane.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @non_leaseable_secret_keys ~w(refresh_token client_secret webhook_secret private_key password)

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Contracts.non_empty_string_schema("credential.id"),
              credential_ref_id:
                Contracts.non_empty_string_schema("credential.credential_ref_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              connection_id:
                Contracts.non_empty_string_schema("credential.connection_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              profile_id:
                Contracts.non_empty_string_schema("credential.profile_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              subject: Contracts.non_empty_string_schema("credential.subject"),
              auth_type: Zoi.atom(),
              version: Zoi.integer() |> Zoi.min(1) |> Zoi.default(1),
              scopes: Contracts.string_list_schema("credential.scopes") |> Zoi.default([]),
              secret: Contracts.any_map_schema() |> Zoi.default(%{}),
              lease_fields:
                Contracts.string_list_schema("credential.lease_fields")
                |> Zoi.nullish()
                |> Zoi.optional(),
              expires_at:
                Contracts.datetime_schema("credential.expires_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              refresh_token_expires_at:
                Contracts.datetime_schema("credential.refresh_token_expires_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              source: Zoi.atom() |> Zoi.nullish() |> Zoi.optional(),
              source_ref: Contracts.any_map_schema() |> Zoi.nullish() |> Zoi.optional(),
              supersedes_credential_id:
                Contracts.non_empty_string_schema("credential.supersedes_credential_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              revoked_at:
                Contracts.datetime_schema("credential.revoked_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = credential), do: validate(credential)

  def new(attrs) do
    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&validate/1)
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = credential),
    do: credential |> validate() |> then(fn {:ok, value} -> value end)

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

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

  defp validate(%__MODULE__{} = credential) do
    credential_ref_id = credential.credential_ref_id || credential.id

    lease_fields =
      case credential.lease_fields do
        nil -> default_lease_fields(credential.secret)
        fields -> normalize_lease_fields(fields)
      end

    {:ok,
     %__MODULE__{
       credential
       | credential_ref_id: credential_ref_id,
         lease_fields: lease_fields
     }}
  end

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
