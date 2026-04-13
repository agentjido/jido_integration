defmodule Jido.Integration.V2.ProjectedCatalog do
  @moduledoc false

  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.TriggerSpec

  @spec connector_entry(Manifest.t()) :: map()
  def connector_entry(%Manifest{} = manifest) do
    connector_module = fetch_connector_module!(manifest)
    projected_operations = ConsumerProjection.projected_operations(manifest)
    projected_triggers = ConsumerProjection.projected_triggers(manifest)

    action_projections =
      Enum.map(projected_operations, fn operation ->
        ConsumerProjection.action_projection!(connector_module, operation.operation_id)
      end)

    sensor_projections =
      Enum.map(projected_triggers, fn trigger ->
        ConsumerProjection.sensor_projection!(connector_module, trigger.trigger_id)
      end)

    plugin_projection = ConsumerProjection.plugin_projection!(connector_module)

    %{
      connector_id: manifest.connector,
      display_name: manifest.catalog.display_name,
      description: manifest.catalog.description,
      category: manifest.catalog.category,
      tags: manifest.catalog.tags,
      docs_refs: manifest.catalog.docs_refs,
      maturity: manifest.catalog.maturity,
      publication: manifest.catalog.publication,
      generated_plugin: %{
        module: plugin_projection.module,
        name: plugin_projection.name,
        state_key: plugin_projection.state_key
      },
      generated_action_names: Enum.map(action_projections, & &1.action_name),
      generated_sensor_names: Enum.map(sensor_projections, & &1.jido_name),
      common_projected_operations:
        Enum.zip(projected_operations, action_projections)
        |> Enum.map(fn {operation, projection} -> operation_entry(operation, projection) end),
      common_projected_triggers:
        Enum.zip(projected_triggers, sensor_projections)
        |> Enum.map(fn {trigger, projection} -> trigger_entry(trigger, projection) end)
    }
  end

  defp operation_entry(%OperationSpec{} = operation, projection) do
    %{
      operation_id: operation.operation_id,
      display_name: operation.display_name,
      description: projection.description,
      normalized_id: projection.normalized_id,
      action_name: projection.action_name,
      generated_module: projection.module,
      runtime_class: operation.runtime_class,
      required_scopes: required_scopes(operation.permissions),
      input_json_schema: Zoi.to_json_schema(projection.schema),
      output_json_schema: Zoi.to_json_schema(projection.output_schema)
    }
  end

  defp trigger_entry(%TriggerSpec{} = trigger, projection) do
    %{
      trigger_id: trigger.trigger_id,
      display_name: trigger.display_name,
      description: projection.description,
      normalized_id: projection.normalized_id,
      sensor_name: projection.sensor_name,
      jido_sensor_name: projection.jido_name,
      generated_module: projection.module,
      runtime_class: trigger.runtime_class,
      delivery_mode: trigger.delivery_mode,
      required_scopes: required_scopes(trigger.permissions),
      signal_type: projection.signal_type,
      signal_source: projection.signal_source,
      checkpoint: trigger.checkpoint,
      dedupe: trigger.dedupe,
      config_json_schema: Zoi.to_json_schema(projection.config_schema),
      signal_json_schema: Zoi.to_json_schema(projection.signal_schema)
    }
  end

  defp fetch_connector_module!(%Manifest{} = manifest) do
    connector_module = Contracts.get(manifest.metadata, :connector_module)

    if is_atom(connector_module) and function_exported?(connector_module, :manifest, 0) do
      connector_module
    else
      raise ArgumentError,
            "registered manifest #{inspect(manifest.connector)} is missing connector_module metadata"
    end
  end

  defp required_scopes(permissions) do
    permissions
    |> Contracts.get(:required_scopes, [])
    |> Contracts.normalize_string_list!("projected_catalog.required_scopes")
  end
end
