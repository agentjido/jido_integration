defmodule Jido.Integration.V2.Connectors.Notion.SchemaValidator do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.Notion.SchemaContext
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Redaction

  @spec validate_input(String.t(), map(), map(), SchemaContext.t() | nil) :: :ok | {:error, map()}
  def validate_input(_capability_id, _metadata, _params, nil), do: :ok

  def validate_input(capability_id, metadata, params, %SchemaContext{} = schema_context)
      when is_binary(capability_id) and is_map(metadata) and is_map(params) do
    issues =
      metadata
      |> Contracts.get(:schema_slots, [])
      |> Enum.filter(&(Contracts.get(&1, :surface) == :input))
      |> Enum.flat_map(&validate_slot(&1, params, schema_context))

    case issues do
      [] ->
        :ok

      _issues ->
        {:error,
         preflight_validation(
           "Notion rejected #{capability_id} during connector preflight schema validation",
           issues,
           SchemaContext.summary(schema_context)
         )}
    end
  end

  defp validate_slot(slot, params, schema_context) do
    source = Contracts.get(slot, :source)
    path = Contracts.get(slot, :path, [])

    case Contracts.get(slot, :kind) do
      :data_source_properties ->
        params
        |> path_get(path)
        |> validate_property_map(path, source, schema_context)

      :data_source_filter ->
        params
        |> path_get(path)
        |> validate_filter(path, source, schema_context)

      :data_source_sorts ->
        params
        |> path_get(path)
        |> validate_sorts(path, source, schema_context)

      _other ->
        []
    end
  end

  defp validate_property_map(properties, path, source, %SchemaContext{} = schema_context)
       when is_map(properties) do
    Enum.flat_map(properties, fn {property_name, _value} ->
      property_name = to_string(property_name)

      unknown_property_issues(
        schema_context,
        :data_source_properties,
        path ++ [property_name],
        property_name,
        source
      )
    end)
  end

  defp validate_property_map(_properties, _path, _source, _schema_context), do: []

  defp validate_filter(filter, path, source, %SchemaContext{} = schema_context)
       when is_map(filter) do
    validate_filter_property(filter, path, source, schema_context) ++
      validate_filter_branches(filter, path, source, schema_context)
  end

  defp validate_filter(_filter, _path, _source, _schema_context), do: []

  defp validate_sorts(sorts, path, source, %SchemaContext{} = schema_context)
       when is_list(sorts) do
    Enum.flat_map(Enum.with_index(sorts), fn {sort, index} ->
      validate_sort(sort, index, path, source, schema_context)
    end)
  end

  defp validate_sorts(_sorts, _path, _source, _schema_context), do: []

  defp path_get(map, [segment | rest]) when is_map(map) do
    case Contracts.get(map, String.to_atom(segment)) do
      nil -> nil
      value when rest == [] -> value
      value when is_map(value) -> path_get(value, rest)
      _other -> nil
    end
  end

  defp path_get(_map, []), do: nil

  defp preflight_validation(message, issues, schema_context_summary) do
    %{
      code: "notion.preflight_validation",
      class: "invalid_request",
      retryability: :terminal,
      message: message,
      upstream_context:
        %{
          phase: :preflight,
          issues: Redaction.redact(issues)
        }
        |> maybe_put(:schema_context, Redaction.redact(schema_context_summary))
    }
  end

  defp validate_filter_property(filter, path, source, %SchemaContext{} = schema_context) do
    case Contracts.get(filter, :property) do
      property_name when is_binary(property_name) ->
        unknown_property_issues(
          schema_context,
          :data_source_filter,
          path ++ ["property"],
          property_name,
          source
        )

      _other ->
        []
    end
  end

  defp validate_filter_branches(filter, path, source, %SchemaContext{} = schema_context) do
    Enum.flat_map(["and", "or"], fn branch ->
      filter
      |> branch_filters(branch)
      |> Enum.with_index()
      |> Enum.flat_map(fn {nested_filter, index} ->
        validate_filter(
          nested_filter,
          path ++ [branch, Integer.to_string(index)],
          source,
          schema_context
        )
      end)
    end)
  end

  defp branch_filters(filter, branch) do
    case Contracts.get(filter, String.to_atom(branch)) do
      filters when is_list(filters) -> filters
      _other -> []
    end
  end

  defp validate_sort(sort, index, path, source, %SchemaContext{} = schema_context) do
    case Contracts.get(sort, :property) do
      property_name when is_binary(property_name) ->
        unknown_property_issues(
          schema_context,
          :data_source_sorts,
          path ++ [Integer.to_string(index), "property"],
          property_name,
          source
        )

      _other ->
        []
    end
  end

  defp unknown_property_issues(schema_context, kind, path, property_name, source) do
    if SchemaContext.property_known?(schema_context, property_name) do
      []
    else
      [
        %{
          kind: kind,
          path: path,
          property: property_name,
          source: source
        }
      ]
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
