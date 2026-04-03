defmodule Jido.Integration.V2.CredentialRef do
  @moduledoc """
  Opaque control-plane-owned credential handle.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Contracts.non_empty_string_schema("credential_ref.id"),
              connection_id:
                Contracts.non_empty_string_schema("credential_ref.connection_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              profile_id:
                Contracts.non_empty_string_schema("credential_ref.profile_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              subject: Contracts.non_empty_string_schema("credential_ref.subject"),
              current_credential_id:
                Contracts.non_empty_string_schema("credential_ref.current_credential_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              scopes: Contracts.string_list_schema("credential_ref.scopes") |> Zoi.default([]),
              lease_fields:
                Contracts.string_list_schema("credential_ref.lease_fields") |> Zoi.default([]),
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
  def new(%__MODULE__{} = credential_ref), do: validate(credential_ref)

  def new(attrs) do
    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&validate/1)
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = credential_ref),
    do: credential_ref |> validate() |> then(fn {:ok, value} -> value end)

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  defp validate(%__MODULE__{} = credential_ref) do
    {:ok,
     %__MODULE__{
       credential_ref
       | current_credential_id: credential_ref.current_credential_id || credential_ref.id
     }}
  end
end
