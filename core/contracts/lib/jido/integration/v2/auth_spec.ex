defmodule Jido.Integration.V2.AuthSpec do
  @moduledoc """
  Authored auth contract for a connector manifest.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @binding_kinds [:connection_id, :tenant, :none]
  @auth_types [:oauth2, :api_token, :session_token, :none]

  @schema Zoi.struct(
            __MODULE__,
            %{
              binding_kind: Contracts.enumish_schema(@binding_kinds, "auth.binding_kind"),
              auth_type: Contracts.enumish_schema(@auth_types, "auth.auth_type"),
              install: Contracts.any_map_schema(),
              reauth: Contracts.any_map_schema(),
              requested_scopes: Contracts.string_list_schema("auth.requested_scopes"),
              lease_fields: Contracts.string_list_schema("auth.lease_fields"),
              secret_names: Contracts.string_list_schema("auth.secret_names"),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type binding_kind :: :connection_id | :tenant | :none
  @type auth_type :: :oauth2 | :api_token | :session_token | :none

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = auth_spec), do: {:ok, auth_spec}
  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = auth_spec), do: auth_spec
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)
end
