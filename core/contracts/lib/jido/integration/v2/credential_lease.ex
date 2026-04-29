defmodule Jido.Integration.V2.CredentialLease do
  @moduledoc """
  Short-lived execution material derived from a durable `CredentialRef`.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @schema Zoi.struct(
            __MODULE__,
            %{
              lease_id: Contracts.non_empty_string_schema("credential_lease.lease_id"),
              tenant_id: Contracts.non_empty_string_schema("credential_lease.tenant_id"),
              credential_ref_id:
                Contracts.non_empty_string_schema("credential_lease.credential_ref_id"),
              credential_id:
                Contracts.non_empty_string_schema("credential_lease.credential_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              connection_id:
                Contracts.non_empty_string_schema("credential_lease.connection_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              profile_id:
                Contracts.non_empty_string_schema("credential_lease.profile_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              subject: Contracts.non_empty_string_schema("credential_lease.subject"),
              scopes: Contracts.string_list_schema("credential_lease.scopes") |> Zoi.default([]),
              payload: Contracts.any_map_schema(),
              lease_fields:
                Contracts.string_list_schema("credential_lease.lease_fields")
                |> Zoi.nullish()
                |> Zoi.optional(),
              issued_at:
                Contracts.datetime_schema("credential_lease.issued_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              expires_at: Contracts.datetime_schema("credential_lease.expires_at"),
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
  def new(%__MODULE__{} = credential_lease), do: validate(credential_lease)

  def new(attrs) do
    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&validate/1)
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = credential_lease) do
    case validate(credential_lease) do
      {:ok, lease} -> lease
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  @spec expired?(t(), DateTime.t()) :: boolean()
  def expired?(%__MODULE__{expires_at: %DateTime{} = expires_at}, %DateTime{} = now) do
    DateTime.compare(expires_at, now) != :gt
  end

  defp validate(%__MODULE__{} = credential_lease) do
    issued_at = credential_lease.issued_at || Contracts.now()
    lease_fields = credential_lease.lease_fields || default_lease_fields(credential_lease.payload)

    if DateTime.compare(credential_lease.expires_at, issued_at) == :gt do
      {:ok,
       %__MODULE__{
         credential_lease
         | credential_id: credential_lease.credential_id || credential_lease.credential_ref_id,
           issued_at: issued_at,
           lease_fields: lease_fields
       }}
    else
      {:error,
       ArgumentError.exception(
         "credential lease expires_at must be after issued_at: #{inspect({issued_at, credential_lease.expires_at})}"
       )}
    end
  end

  defp default_lease_fields(payload) when is_map(payload) do
    payload
    |> Map.keys()
    |> Enum.map(fn
      key when is_atom(key) -> Atom.to_string(key)
      key when is_binary(key) -> key
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
