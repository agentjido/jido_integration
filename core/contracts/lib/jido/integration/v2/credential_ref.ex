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
              subject: Contracts.non_empty_string_schema("credential_ref.subject"),
              scopes: Contracts.string_list_schema("credential_ref.scopes") |> Zoi.default([]),
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
  def new(%__MODULE__{} = credential_ref), do: {:ok, credential_ref}
  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = credential_ref), do: credential_ref
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)
end
