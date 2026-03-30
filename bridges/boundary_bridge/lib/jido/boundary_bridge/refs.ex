defmodule Jido.BoundaryBridge.Refs do
  @moduledoc """
  Cross-layer continuity refs carried through the bridge contract.
  """

  alias Jido.BoundaryBridge.Contracts
  alias Jido.BoundaryBridge.Schema

  @schema Zoi.struct(
            __MODULE__,
            %{
              target_id:
                Contracts.non_empty_string_schema("refs.target_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              lease_ref:
                Contracts.non_empty_string_schema("refs.lease_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              surface_ref:
                Contracts.non_empty_string_schema("refs.surface_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              runtime_ref:
                Contracts.non_empty_string_schema("refs.runtime_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              correlation_id: Contracts.non_empty_string_schema("refs.correlation_id"),
              request_id: Contracts.non_empty_string_schema("refs.request_id")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = refs), do: {:ok, refs}
  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = refs), do: refs
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)
end
