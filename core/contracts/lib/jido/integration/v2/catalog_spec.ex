defmodule Jido.Integration.V2.CatalogSpec do
  @moduledoc """
  Authored catalog metadata for a connector manifest.
  """

  alias Jido.Integration.V2.Contracts

  @maturity_values [:experimental, :alpha, :beta, :ga]
  @publication_values [:internal, :public, :private]

  @enforce_keys [
    :display_name,
    :description,
    :category,
    :tags,
    :docs_refs,
    :maturity,
    :publication
  ]
  defstruct [
    :display_name,
    :description,
    :category,
    :tags,
    :docs_refs,
    :maturity,
    :publication,
    metadata: %{}
  ]

  @type maturity :: :experimental | :alpha | :beta | :ga
  @type publication :: :internal | :public | :private

  @type t :: %__MODULE__{
          display_name: String.t(),
          description: String.t(),
          category: String.t(),
          tags: [String.t()],
          docs_refs: [String.t()],
          maturity: maturity(),
          publication: publication(),
          metadata: map()
        }

  @spec new!(map() | t()) :: t()
  def new!(%__MODULE__{} = catalog_spec), do: catalog_spec

  def new!(attrs) when is_map(attrs) do
    attrs = Map.new(attrs)

    struct!(__MODULE__, %{
      display_name:
        Contracts.validate_non_empty_string!(
          Contracts.fetch!(attrs, :display_name),
          "catalog.display_name"
        ),
      description:
        Contracts.validate_non_empty_string!(
          Contracts.fetch!(attrs, :description),
          "catalog.description"
        ),
      category:
        Contracts.validate_non_empty_string!(
          Contracts.fetch!(attrs, :category),
          "catalog.category"
        ),
      tags: Contracts.normalize_string_list!(Contracts.fetch!(attrs, :tags), "catalog.tags"),
      docs_refs:
        Contracts.normalize_string_list!(Contracts.fetch!(attrs, :docs_refs), "catalog.docs_refs"),
      maturity: validate_maturity!(Contracts.fetch!(attrs, :maturity)),
      publication: validate_publication!(Contracts.fetch!(attrs, :publication)),
      metadata: Contracts.validate_map!(Map.get(attrs, :metadata, %{}), "catalog.metadata")
    })
  end

  def new!(attrs) do
    raise ArgumentError, "catalog spec must be a map, got: #{inspect(attrs)}"
  end

  defp validate_maturity!(maturity) when maturity in @maturity_values, do: maturity

  defp validate_maturity!(maturity) when is_binary(maturity) do
    normalize_enum_string!(maturity, @maturity_values, "catalog.maturity")
  end

  defp validate_maturity!(maturity) do
    raise ArgumentError, "invalid catalog.maturity: #{inspect(maturity)}"
  end

  defp validate_publication!(publication) when publication in @publication_values, do: publication

  defp validate_publication!(publication) when is_binary(publication) do
    normalize_enum_string!(publication, @publication_values, "catalog.publication")
  end

  defp validate_publication!(publication) do
    raise ArgumentError, "invalid catalog.publication: #{inspect(publication)}"
  end

  defp normalize_enum_string!(value, allowed, field_name) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> raise ArgumentError, "invalid #{field_name}: #{inspect(value)}"
      enum_value -> enum_value
    end
  end
end
