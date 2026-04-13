defmodule Jido.Integration.V2.CatalogSpec do
  @moduledoc """
  Authored catalog metadata for a connector manifest.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @maturity_values [:experimental, :alpha, :beta, :ga]
  @publication_values [:internal, :public, :private]

  @schema Zoi.struct(
            __MODULE__,
            %{
              display_name: Contracts.non_empty_string_schema("catalog.display_name"),
              description: Contracts.non_empty_string_schema("catalog.description"),
              category: Contracts.non_empty_string_schema("catalog.category"),
              tags: Contracts.string_list_schema("catalog.tags"),
              docs_refs: Contracts.string_list_schema("catalog.docs_refs"),
              maturity: Contracts.enumish_schema(@maturity_values, "catalog.maturity"),
              publication: Contracts.enumish_schema(@publication_values, "catalog.publication"),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type maturity :: :experimental | :alpha | :beta | :ga
  @type publication :: :internal | :public | :private

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = catalog_spec), do: {:ok, catalog_spec}
  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = catalog_spec), do: catalog_spec
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)
end
