defmodule Jido.Integration.V2.DynamicToolManifest do
  @moduledoc """
  Resolves authored dynamic-tool declarations against connector operation catalogs.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

  @operation_aliases %{
    "linear.comment.update" => "linear.comments.update",
    "linear_graphql" => "linear.graphql.execute"
  }

  @tool_name_aliases %{
    "linear.comment.update" => "linear_comment_update",
    "linear.graphql.execute" => "linear_graphql",
    "linear_graphql" => "linear_graphql"
  }

  @type resolved :: %{
          required(:operations) => [String.t()],
          required(:tools) => [map()],
          required(:host_tools) => [map()],
          required(:metadata) => map()
        }

  @spec resolve(map(), keyword()) :: {:ok, resolved()} | {:error, Exception.t()}
  def resolve(manifest, opts \\ []) when is_map(manifest) and is_list(opts) do
    {:ok, resolve!(manifest, opts)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec resolve!(map(), keyword()) :: resolved()
  def resolve!(manifest, opts \\ [])

  def resolve!(manifest, opts) when is_map(manifest) and is_list(opts) do
    connector_manifests = Keyword.get(opts, :connector_manifests, [])
    authority = authority!(opts)
    operation_index = operation_index!(connector_manifests)

    tools =
      manifest
      |> declared_tools!()
      |> Enum.map(&resolve_tool!(&1, operation_index, authority))

    operations = Enum.map(tools, & &1["operation_id"])

    %{
      operations: operations,
      tools: tools,
      host_tools: Enum.map(tools, &host_tool/1),
      metadata: %{
        "operations" => operations,
        "tool_names" => Enum.map(tools, & &1["name"]),
        "authority_ref" => authority.authority_ref,
        "tenant_ref" => authority.tenant_ref,
        "installation_ref" => authority.installation_ref
      }
    }
  end

  def resolve!(manifest, _opts) do
    raise ArgumentError,
          "dynamic_tool_manifest must be a map, got: #{inspect(manifest)}"
  end

  defp declared_tools!(manifest) do
    case map_value(manifest, :tools) do
      tools when is_list(tools) and tools != [] ->
        tools

      tools ->
        raise ArgumentError,
              "dynamic_tool_manifest.tools must be a non-empty list, got: #{inspect(tools)}"
    end
  end

  defp operation_index!(connector_manifests) when is_list(connector_manifests) do
    connector_manifests
    |> Enum.flat_map(&manifest_operations!/1)
    |> Enum.reduce(%{}, fn {operation_id, entry}, acc ->
      Map.update(acc, operation_id, [entry], &[entry | &1])
    end)
  end

  defp operation_index!(connector_manifests) do
    raise ArgumentError,
          "connector_manifests must be a list, got: #{inspect(connector_manifests)}"
  end

  defp manifest_operations!(%Manifest{} = manifest) do
    Enum.map(manifest.operations, fn %OperationSpec{} = operation ->
      {operation.operation_id, %{manifest: manifest, operation: operation}}
    end)
  end

  defp manifest_operations!(manifest) do
    raise ArgumentError,
          "connector_manifests must contain Jido manifests, got: #{inspect(manifest)}"
  end

  defp resolve_tool!(declaration, operation_index, authority) do
    declared = normalize_declaration!(declaration)
    operation_ids = Enum.map(declared.operation_ids, &canonical_operation_id/1)

    case operation_ids do
      [operation_id] ->
        resolve_single_operation!(declared, operation_id, operation_index, authority)

      [] ->
        raise ArgumentError, "dynamic tool declaration must name one operation"

      _many ->
        raise ArgumentError,
              "dynamic tool #{inspect(declared.name || declaration)} maps to multiple operations"
    end
  end

  defp resolve_single_operation!(declared, operation_id, operation_index, authority) do
    case Map.get(operation_index, operation_id, []) do
      [%{manifest: manifest, operation: operation}] ->
        authorize_operation!(operation, authority)
        manifest_hash = Manifest.canonical_hash(manifest)

        %{
          "name" => declared.name || tool_name_for(declared.raw, operation_id),
          "operation_id" => operation_id,
          "connector" => manifest.connector,
          "catalog_ref" => "#{manifest.connector}:#{operation_id}",
          "manifest_ref" => manifest_ref(manifest.connector, manifest_hash),
          "manifest_hash" => manifest_hash,
          "manifest_state" => manifest_state(manifest),
          "description" => operation.description,
          "allowed_tools" => operation_allowed_tools(operation),
          "input_schema" => json_schema(operation.input_schema),
          "output_schema" => json_schema(operation.output_schema),
          "authority_ref" => authority.authority_ref,
          "tenant_ref" => authority.tenant_ref,
          "installation_ref" => authority.installation_ref
        }

      [] ->
        raise ArgumentError,
              "dynamic tool operation #{inspect(operation_id)} is not present in connector catalogs"

      _duplicates ->
        raise ArgumentError,
              "dynamic tool operation #{inspect(operation_id)} is ambiguous across connector catalogs"
    end
  end

  defp normalize_declaration!(value) when is_binary(value) do
    %{raw: value, name: nil, operation_ids: [value]}
  end

  defp normalize_declaration!(%{} = declaration) do
    operation_ids =
      [
        map_value(declaration, :operation_id),
        map_value(declaration, :operation)
      ]
      |> Enum.reject(&is_nil/1)
      |> List.wrap()
      |> List.flatten()

    operation_ids =
      case map_value(declaration, :operations) do
        nil -> operation_ids
        operations when is_list(operations) -> operation_ids ++ operations
        operation -> operation_ids ++ [operation]
      end

    %{
      raw: map_value(declaration, :operation_id) || map_value(declaration, :operation),
      name: map_value(declaration, :name) || map_value(declaration, :tool_name),
      operation_ids: Enum.map(operation_ids, &operation_id_string!/1)
    }
  end

  defp normalize_declaration!(declaration) do
    raise ArgumentError,
          "dynamic tool declaration must be a string or map, got: #{inspect(declaration)}"
  end

  defp operation_id_string!(value) when is_binary(value) and value != "", do: value

  defp operation_id_string!(value) do
    raise ArgumentError,
          "dynamic tool operation id must be a non-empty string, got: #{inspect(value)}"
  end

  defp canonical_operation_id(operation_id) do
    Map.get(@operation_aliases, operation_id, operation_id)
  end

  defp tool_name_for(raw, operation_id) do
    Map.get(@tool_name_aliases, raw) ||
      Map.get(@tool_name_aliases, operation_id) ||
      operation_id
      |> String.replace(".", "_")
      |> String.replace("-", "_")
  end

  defp host_tool(tool) do
    %{
      "name" => tool["name"],
      "description" => tool["description"],
      "inputSchema" => tool["input_schema"],
      "outputSchema" => tool["output_schema"],
      "metadata" =>
        Map.take(tool, [
          "operation_id",
          "connector",
          "catalog_ref",
          "manifest_ref",
          "manifest_hash",
          "manifest_state",
          "allowed_tools",
          "authority_ref",
          "tenant_ref",
          "installation_ref"
        ])
    }
    |> drop_nil_values()
  end

  defp authorize_operation!(%OperationSpec{} = operation, authority) do
    unless operation.operation_id in authority.allowed_operations do
      raise ArgumentError,
            "dynamic tool operation #{inspect(operation.operation_id)} is not present in Citadel allowed_operations"
    end

    missing_allowed_tools = operation_allowed_tools(operation) -- authority.allowed_tools

    if missing_allowed_tools == [] do
      :ok
    else
      raise ArgumentError,
            "dynamic tool operation #{inspect(operation.operation_id)} requires allowed tools #{inspect(missing_allowed_tools)}"
    end
  end

  defp authority!(opts) do
    allowed_operations =
      opts
      |> Keyword.get(:allowed_operations)
      |> required_string_list!("allowed_operations")

    allowed_tools =
      opts
      |> Keyword.get(:allowed_tools)
      |> required_string_list!("allowed_tools")

    %{
      allowed_operations: allowed_operations,
      allowed_tools: allowed_tools,
      authority_ref: optional_string(Keyword.get(opts, :authority_ref)),
      tenant_ref: optional_string(Keyword.get(opts, :tenant_ref)),
      installation_ref: optional_string(Keyword.get(opts, :installation_ref))
    }
  end

  defp required_string_list!(value, field_name) do
    values = Contracts.normalize_string_list!(value || [], field_name)

    if values == [] do
      raise ArgumentError, "dynamic tool manifest requires Citadel #{field_name}"
    else
      values
    end
  end

  defp operation_allowed_tools(%OperationSpec{} = operation) do
    sandbox = map_value(operation.policy, :sandbox)

    case map_value(sandbox, :allowed_tools) do
      values when is_list(values) -> Contracts.normalize_string_list!(values, "allowed_tools")
      _other -> []
    end
  end

  defp manifest_ref(connector, manifest_hash) do
    "jido://v2/connector_manifest/#{URI.encode_www_form(connector)}/#{manifest_hash}"
  end

  defp manifest_state(%Manifest{metadata: metadata}) do
    metadata
    |> map_value(:manifest_state)
    |> case do
      value when value in [:active, "active"] -> "active"
      value when value in [:stale, "stale"] -> "stale"
      value when value in [:invalid, "invalid"] -> "invalid"
      value when value in [:refresh_required, "refresh_required"] -> "refresh_required"
      value when value in [:quarantined, "quarantined"] -> "quarantined"
      _other -> "active"
    end
  end

  defp json_schema(schema) do
    schema
    |> Zoi.Schema.traverse(&json_schema_compatible/1)
    |> json_schema_compatible()
    |> Zoi.to_json_schema()
  end

  defp json_schema_compatible(%Zoi.Types.Any{} = schema) do
    cond do
      contracts_refinement?(schema, :validate_map_refine) ->
        Contracts.any_map_schema()
        |> preserve_json_schema_meta(schema)

      contracts_refinement?(schema, :validate_positive_integer_refine) ->
        Zoi.integer()
        |> Zoi.gte(1)
        |> preserve_json_schema_meta(schema)

      true ->
        schema
    end
  end

  defp json_schema_compatible(schema), do: schema

  defp contracts_refinement?(schema, refinement_name) when is_atom(refinement_name) do
    Enum.any?(schema.meta.effects, fn
      {:refine, {Contracts, ^refinement_name, _args}} -> true
      _other -> false
    end)
  end

  defp preserve_json_schema_meta(schema, source_schema) do
    source_meta = source_schema.meta

    meta = %{
      schema.meta
      | deprecated: source_meta.deprecated,
        description: source_meta.description,
        error: source_meta.error,
        example: source_meta.example,
        metadata: source_meta.metadata,
        required: source_meta.required,
        typespec: source_meta.typespec
    }

    %{schema | meta: meta}
  end

  defp map_value(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_value, _key), do: nil

  defp optional_string(value) when is_binary(value) and value != "", do: value
  defp optional_string(_value), do: nil

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
