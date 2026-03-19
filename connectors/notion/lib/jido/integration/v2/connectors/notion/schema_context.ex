defmodule Jido.Integration.V2.Connectors.Notion.SchemaContext do
  @moduledoc false

  alias Jido.Integration.V2.Contracts

  @enforce_keys [:context_source, :data_source_id, :properties, :resolved_via, :slot_kinds]
  defstruct [
    :context_source,
    :data_source_id,
    :source_page_id,
    :properties,
    :property_ids,
    :property_names,
    :property_types,
    :resolved_via,
    :slot_kinds
  ]

  @type t :: %__MODULE__{
          context_source: atom(),
          data_source_id: String.t(),
          source_page_id: String.t() | nil,
          properties: map(),
          property_ids: map(),
          property_names: [String.t()],
          property_types: map(),
          resolved_via: [atom()],
          slot_kinds: [atom()]
        }

  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    properties =
      opts
      |> Keyword.get(:properties, %{})
      |> normalize_properties()

    property_names =
      properties
      |> Map.keys()
      |> Enum.sort()

    property_ids =
      Enum.reduce(properties, %{}, fn {name, property}, acc ->
        case Contracts.get(property, :id) do
          property_id when is_binary(property_id) and property_id != "" ->
            Map.put(acc, property_id, name)

          _other ->
            acc
        end
      end)

    property_types =
      Enum.into(properties, %{}, fn {name, property} ->
        {name, Contracts.get(property, :type)}
      end)

    struct!(__MODULE__, %{
      context_source: Keyword.fetch!(opts, :context_source),
      data_source_id: Keyword.fetch!(opts, :data_source_id),
      source_page_id: Keyword.get(opts, :source_page_id),
      properties: properties,
      property_ids: property_ids,
      property_names: property_names,
      property_types: property_types,
      resolved_via: Keyword.get(opts, :resolved_via, []),
      slot_kinds:
        opts
        |> Keyword.get(:slot_kinds, [])
        |> Enum.uniq()
        |> Enum.sort_by(&Atom.to_string/1)
    })
  end

  @spec property_known?(t(), String.t()) :: boolean()
  def property_known?(%__MODULE__{} = context, property_ref) when is_binary(property_ref) do
    Map.has_key?(context.properties, property_ref) or
      Map.has_key?(context.property_ids, property_ref)
  end

  def property_known?(%__MODULE__{}, _property_ref), do: false

  @spec summary(t() | nil) :: map() | nil
  def summary(nil), do: nil

  def summary(%__MODULE__{} = context) do
    %{
      context_source: context.context_source,
      data_source_id: context.data_source_id,
      property_names: context.property_names,
      resolved_via: context.resolved_via,
      slot_kinds: context.slot_kinds
    }
    |> maybe_put(:source_page_id, context.source_page_id)
  end

  defp normalize_properties(properties) when is_map(properties) do
    Map.new(properties, fn {name, property} ->
      {to_string(name), normalize_property(property)}
    end)
  end

  defp normalize_properties(_properties), do: %{}

  defp normalize_property(property) when is_map(property) do
    Map.new(property, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_property(property), do: %{"value" => property}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
