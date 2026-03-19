defmodule Jido.Integration.V2.Conformance.Suites.ConsumerSurfaceProjection do
  @moduledoc false

  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport
  alias Jido.Integration.V2.Contracts

  @spec run(map()) :: SuiteResult.t()
  def run(%{manifest: manifest}) do
    checks =
      Enum.flat_map(manifest.operations, &operation_checks/1) ++
        Enum.flat_map(manifest.triggers, &trigger_checks/1)

    SuiteResult.from_checks(
      :consumer_surface_projection,
      checks,
      "Common consumer surfaces stay explicit, normalized, and schema-backed"
    )
  end

  defp operation_checks(operation) do
    consumer_surface = Map.get(operation, :consumer_surface, %{})
    schema_policy = Map.get(operation, :schema_policy, %{})
    mode = SuiteSupport.fetch(consumer_surface, :mode)
    normalized_id = SuiteSupport.fetch(consumer_surface, :normalized_id)
    action_name = SuiteSupport.fetch(consumer_surface, :action_name)
    reason = SuiteSupport.fetch(consumer_surface, :reason)
    input_mode = SuiteSupport.fetch(schema_policy, :input)
    output_mode = SuiteSupport.fetch(schema_policy, :output)
    justification = SuiteSupport.fetch(schema_policy, :justification)

    [
      SuiteSupport.check(
        "#{operation.operation_id}.consumer_surface.mode_declared",
        mode in [:common, :connector_local],
        "operations must declare whether they belong to the normalized common consumer surface or stay connector-local"
      ),
      SuiteSupport.check(
        "#{operation.operation_id}.common_surface.metadata",
        common_surface_metadata_valid?(mode, normalized_id, action_name, reason),
        "common projected operations require normalized_id and action_name; connector-local operations require a reason"
      ),
      SuiteSupport.check(
        "#{operation.operation_id}.common_surface.schemas_defined",
        common_surface_schema_policy_valid?(mode, input_mode, output_mode),
        "common projected operations must not rely on passthrough schemas"
      ),
      SuiteSupport.check(
        "#{operation.operation_id}.schema_policy.placeholder_exemption",
        placeholder_schema_policy_valid?(
          input_mode,
          output_mode,
          justification,
          Map.get(operation, :input_schema),
          Map.get(operation, :output_schema)
        ),
        "placeholder input/output schemas require an explicit passthrough justification"
      )
    ]
  end

  defp trigger_checks(trigger) do
    consumer_surface = Map.get(trigger, :consumer_surface, %{})
    schema_policy = Map.get(trigger, :schema_policy, %{})
    mode = SuiteSupport.fetch(consumer_surface, :mode)
    normalized_id = SuiteSupport.fetch(consumer_surface, :normalized_id)
    sensor_name = SuiteSupport.fetch(consumer_surface, :sensor_name)
    reason = SuiteSupport.fetch(consumer_surface, :reason)
    config_mode = SuiteSupport.fetch(schema_policy, :config)
    signal_mode = SuiteSupport.fetch(schema_policy, :signal)
    justification = SuiteSupport.fetch(schema_policy, :justification)

    [
      SuiteSupport.check(
        "#{trigger.trigger_id}.consumer_surface.mode_declared",
        mode in [:common, :connector_local],
        "triggers must declare whether they belong to the normalized common consumer surface or stay connector-local"
      ),
      SuiteSupport.check(
        "#{trigger.trigger_id}.common_surface.metadata",
        common_surface_metadata_valid?(mode, normalized_id, sensor_name, reason),
        "common projected triggers require normalized_id and sensor_name; connector-local triggers require a reason"
      ),
      SuiteSupport.check(
        "#{trigger.trigger_id}.common_surface.schemas_defined",
        common_surface_schema_policy_valid?(mode, config_mode, signal_mode),
        "common projected triggers must not rely on passthrough schemas"
      ),
      SuiteSupport.check(
        "#{trigger.trigger_id}.schema_policy.placeholder_exemption",
        placeholder_schema_policy_valid?(
          config_mode,
          signal_mode,
          justification,
          Map.get(trigger, :config_schema),
          Map.get(trigger, :signal_schema)
        ),
        "placeholder config/signal schemas require an explicit passthrough justification"
      )
    ]
  end

  defp common_surface_metadata_valid?(:common, normalized_id, action_or_sensor_name, reason) do
    present_string?(normalized_id) and present_string?(action_or_sensor_name) and
      not present_string?(reason)
  end

  defp common_surface_metadata_valid?(
         :connector_local,
         normalized_id,
         action_or_sensor_name,
         reason
       ) do
    present_string?(reason) and not present_string?(normalized_id) and
      not present_string?(action_or_sensor_name)
  end

  defp common_surface_metadata_valid?(_mode, _normalized_id, _action_or_sensor_name, _reason),
    do: false

  defp common_surface_schema_policy_valid?(:common, left_mode, right_mode) do
    left_mode in [:defined, :dynamic] and right_mode in [:defined, :dynamic]
  end

  defp common_surface_schema_policy_valid?(:connector_local, _left_mode, _right_mode), do: true
  defp common_surface_schema_policy_valid?(_mode, _left_mode, _right_mode), do: false

  defp placeholder_schema_policy_valid?(
         left_mode,
         right_mode,
         justification,
         left_schema,
         right_schema
       ) do
    passthrough? = left_mode == :passthrough or right_mode == :passthrough

    placeholder? =
      Contracts.placeholder_zoi_schema?(left_schema) or
        Contracts.placeholder_zoi_schema?(right_schema)

    cond do
      passthrough? -> present_string?(justification)
      placeholder? -> false
      present_string?(justification) -> false
      true -> true
    end
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
end
