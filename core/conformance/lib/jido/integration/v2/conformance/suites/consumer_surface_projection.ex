defmodule Jido.Integration.V2.Conformance.Suites.ConsumerSurfaceProjection do
  @moduledoc false

  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport
  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.TriggerSpec

  @spec run(map()) :: SuiteResult.t()
  def run(%{connector_module: connector_module, manifest: manifest}) do
    projected_operations = ConsumerProjection.projected_operations(manifest)
    projected_triggers = ConsumerProjection.projected_triggers(manifest)

    checks =
      Enum.flat_map(manifest.operations, &operation_checks/1) ++
        Enum.flat_map(manifest.triggers, &trigger_checks/1) ++
        Enum.flat_map(projected_operations, &generated_action_checks(connector_module, &1)) ++
        generated_plugin_checks(connector_module, projected_operations, projected_triggers) ++
        Enum.flat_map(projected_triggers, &generated_sensor_checks(connector_module, &1))

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
    sensor_projection = trigger |> Map.get(:jido, %{}) |> Contracts.get(:sensor, %{})
    mode = SuiteSupport.fetch(consumer_surface, :mode)
    normalized_id = SuiteSupport.fetch(consumer_surface, :normalized_id)
    sensor_name = SuiteSupport.fetch(consumer_surface, :sensor_name)
    reason = SuiteSupport.fetch(consumer_surface, :reason)
    jido_name = Contracts.get(sensor_projection, :name)
    signal_type = Contracts.get(sensor_projection, :signal_type)
    signal_source = Contracts.get(sensor_projection, :signal_source)
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
        "#{trigger.trigger_id}.common_surface.jido_sensor_name",
        common_trigger_jido_sensor_name_valid?(mode, jido_name),
        "common projected triggers require jido.sensor.name; connector-local triggers may omit it"
      ),
      SuiteSupport.check(
        "#{trigger.trigger_id}.common_surface.signal_metadata",
        common_trigger_signal_metadata_valid?(mode, signal_type, signal_source),
        "common projected triggers require jido.sensor.signal_type and jido.sensor.signal_source; connector-local triggers may omit them"
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

  defp common_trigger_jido_sensor_name_valid?(:common, jido_name), do: present_string?(jido_name)
  defp common_trigger_jido_sensor_name_valid?(:connector_local, _jido_name), do: true
  defp common_trigger_jido_sensor_name_valid?(_mode, _jido_name), do: false

  defp common_trigger_signal_metadata_valid?(:common, signal_type, signal_source) do
    present_string?(signal_type) and present_string?(signal_source)
  end

  defp common_trigger_signal_metadata_valid?(:connector_local, _signal_type, _signal_source),
    do: true

  defp common_trigger_signal_metadata_valid?(_mode, _signal_type, _signal_source), do: false

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

  defp generated_action_checks(connector_module, %OperationSpec{} = operation) do
    case safe_projection(fn ->
           ConsumerProjection.action_projection!(connector_module, operation.operation_id)
         end) do
      {:ok, expected_projection} ->
        module = expected_projection.module

        [
          SuiteSupport.check(
            "#{operation.operation_id}.generated_action.module_resolves",
            generated_action_module_resolves?(module),
            "projected common operations must ship a loadable generated action module"
          ),
          SuiteSupport.check(
            "#{operation.operation_id}.generated_action.projection_consistent",
            generated_action_projection_consistent?(module, expected_projection),
            "generated action modules must match the authored common projection metadata"
          )
        ]

      {:error, reason} ->
        generated_projection_error_checks(
          operation.operation_id,
          :generated_action,
          "generated action projection could not be derived: #{reason}"
        )
    end
  end

  defp generated_plugin_checks(connector_module, projected_operations, projected_triggers) do
    if projected_operations == [] and projected_triggers == [] do
      []
    else
      do_generated_plugin_checks(connector_module, projected_operations, projected_triggers)
    end
  end

  defp generated_sensor_checks(connector_module, %TriggerSpec{} = trigger) do
    case safe_projection(fn ->
           ConsumerProjection.sensor_projection!(connector_module, trigger.trigger_id)
         end) do
      {:ok, expected_projection} ->
        module = expected_projection.module

        [
          SuiteSupport.check(
            "#{trigger.trigger_id}.generated_sensor.module_resolves",
            generated_sensor_module_resolves?(module),
            "projected common triggers must ship a loadable generated sensor module"
          ),
          SuiteSupport.check(
            "#{trigger.trigger_id}.generated_sensor.projection_consistent",
            generated_sensor_projection_consistent?(module, expected_projection),
            "generated sensor modules must match the authored common projection metadata"
          )
        ]

      {:error, reason} ->
        generated_projection_error_checks(
          trigger.trigger_id,
          :generated_sensor,
          "generated sensor projection could not be derived: #{reason}"
        )
    end
  end

  defp generated_action_module_resolves?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :generated_action_projection, 0) and
      function_exported?(module, :operation_id, 0) and function_exported?(module, :run, 2) and
      function_exported?(module, :schema, 0) and function_exported?(module, :output_schema, 0)
  end

  defp generated_action_projection_consistent?(module, expected_projection) do
    generated_action_module_resolves?(module) and
      action_projection_equivalent?(module.generated_action_projection(), expected_projection) and
      module.operation_id() == expected_projection.operation_id and
      module.name() == expected_projection.action_name and
      zoi_schema_equivalent?(module.schema(), expected_projection.schema) and
      zoi_schema_equivalent?(module.output_schema(), expected_projection.output_schema)
  end

  defp generated_plugin_module_resolves?(module) do
    Code.ensure_loaded?(module) and
      Enum.all?(plugin_exports(), fn {function_name, arity} ->
        function_exported?(module, function_name, arity)
      end)
  end

  defp generated_plugin_projection_consistent?(module, expected_projection) do
    generated_plugin_module_resolves?(module) and
      plugin_projection_equivalent?(module.generated_plugin_projection(), expected_projection) and
      module.name() == expected_projection.name and
      module.state_key() == expected_projection.state_key and
      zoi_schema_equivalent?(module.config_schema(), expected_projection.config_schema)
  end

  defp generated_plugin_actions_match?(module, projected_operations, connector_module) do
    expected_action_modules = expected_action_modules(projected_operations, connector_module)

    generated_plugin_module_resolves?(module) and
      module.actions() == expected_action_modules and
      module.manifest().actions == expected_action_modules and
      module.plugin_spec(%{}).actions == expected_action_modules
  rescue
    _error -> false
  end

  defp generated_plugin_subscriptions_match?(module, projected_triggers, connector_module) do
    expected_subscriptions = expected_subscriptions(projected_triggers, connector_module)

    generated_plugin_module_resolves?(module) and
      module.subscriptions() == expected_subscriptions and
      module.subscriptions(%{}, %{}) == [] and
      module.manifest().subscriptions == expected_subscriptions
  rescue
    _error -> false
  end

  defp generated_sensor_module_resolves?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :generated_sensor_projection, 0) and
      function_exported?(module, :trigger_id, 0) and function_exported?(module, :init, 2) and
      function_exported?(module, :handle_event, 2) and function_exported?(module, :schema, 0)
  end

  defp generated_sensor_projection_consistent?(module, expected_projection) do
    generated_sensor_module_resolves?(module) and
      sensor_projection_equivalent?(module.generated_sensor_projection(), expected_projection) and
      module.trigger_id() == expected_projection.trigger_id and
      module.name() == expected_projection.jido_name and
      zoi_schema_equivalent?(module.schema(), expected_projection.sensor_schema)
  end

  defp action_projection_equivalent?(left, right) do
    projection_field_equal?(left, right, [
      :connector_module,
      :plugin_module,
      :module,
      :operation_id,
      :normalized_id,
      :action_name,
      :description,
      :category,
      :tags
    ]) and
      zoi_schema_equivalent?(left.schema, right.schema) and
      zoi_schema_equivalent?(left.output_schema, right.output_schema)
  end

  defp plugin_projection_equivalent?(left, right) do
    projection_field_equal?(left, right, [
      :connector_module,
      :module,
      :name,
      :state_key,
      :description,
      :category,
      :tags,
      :actions
    ]) and
      zoi_schema_equivalent?(left.config_schema, right.config_schema)
  end

  defp sensor_projection_equivalent?(left, right) do
    projection_field_equal?(left, right, [
      :connector_id,
      :connector_module,
      :plugin_module,
      :module,
      :trigger_id,
      :normalized_id,
      :delivery_mode,
      :auth_binding_kind,
      :sensor_name,
      :jido_name,
      :description,
      :category,
      :tags,
      :signal_type,
      :signal_source,
      :checkpoint,
      :polling
    ]) and
      zoi_schema_equivalent?(left.config_schema, right.config_schema) and
      zoi_schema_equivalent?(left.sensor_schema, right.sensor_schema) and
      zoi_schema_equivalent?(left.signal_schema, right.signal_schema)
  end

  defp projection_field_equal?(left, right, fields) do
    Enum.all?(fields, fn field ->
      Map.get(left, field) == Map.get(right, field)
    end)
  end

  defp zoi_schema_equivalent?(left, right) do
    normalize_schema_term(left) == normalize_schema_term(right)
  end

  defp normalize_schema_term(%module{} = value) when is_atom(module) do
    {module, value |> Map.from_struct() |> normalize_schema_term()}
  end

  defp normalize_schema_term(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {key, normalize_schema_term(nested)} end)
    |> Enum.sort_by(fn {key, _nested} -> inspect(key) end)
  end

  defp normalize_schema_term(value) when is_list(value) do
    if Keyword.keyword?(value) do
      value
      |> Enum.map(fn {key, nested} -> {key, normalize_schema_term(nested)} end)
      |> Enum.sort_by(fn {key, _nested} -> inspect(key) end)
    else
      Enum.map(value, &normalize_schema_term/1)
    end
  end

  defp normalize_schema_term(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&normalize_schema_term/1)
    |> List.to_tuple()
  end

  defp normalize_schema_term(value), do: value

  defp generated_projection_error_checks(id, prefix, message) do
    [
      SuiteSupport.check(
        "#{id}.#{prefix}.module_resolves",
        false,
        message
      ),
      SuiteSupport.check(
        "#{id}.#{prefix}.projection_consistent",
        false,
        message
      )
    ]
  end

  defp safe_projection(fun) do
    {:ok, fun.()}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp do_generated_plugin_checks(connector_module, projected_operations, projected_triggers) do
    connector_id = connector_module.manifest().connector

    case safe_projection(fn -> ConsumerProjection.plugin_projection!(connector_module) end) do
      {:ok, expected_projection} ->
        plugin_projection_checks(
          connector_id,
          expected_projection,
          projected_operations,
          projected_triggers,
          connector_module
        )

      {:error, reason} ->
        plugin_projection_error_checks(connector_id, reason)
    end
  end

  defp plugin_projection_checks(
         connector_id,
         expected_projection,
         projected_operations,
         projected_triggers,
         connector_module
       ) do
    module = expected_projection.module

    [
      SuiteSupport.check(
        "#{connector_id}.generated.plugin.module_resolves",
        generated_plugin_module_resolves?(module),
        "connectors with common projected surfaces must ship a loadable generated plugin module"
      ),
      SuiteSupport.check(
        "#{connector_id}.generated.plugin.projection_consistent",
        generated_plugin_projection_consistent?(module, expected_projection),
        "generated plugin modules must match the authored common projection metadata"
      ),
      SuiteSupport.check(
        "#{connector_id}.generated.plugin.actions_match",
        generated_plugin_actions_match?(module, projected_operations, connector_module),
        "generated plugin action lists must match the projected common action modules"
      ),
      SuiteSupport.check(
        "#{connector_id}.generated.plugin.subscriptions_match",
        generated_plugin_subscriptions_match?(module, projected_triggers, connector_module),
        "generated plugin subscriptions must match the projected common sensor modules"
      )
    ]
  end

  defp plugin_projection_error_checks(connector_id, reason) do
    [
      SuiteSupport.check(
        "#{connector_id}.generated.plugin.module_resolves",
        false,
        "generated plugin projection could not be derived: #{reason}"
      ),
      SuiteSupport.check(
        "#{connector_id}.generated.plugin.projection_consistent",
        false,
        "generated plugin projection could not be derived: #{reason}"
      ),
      SuiteSupport.check(
        "#{connector_id}.generated.plugin.actions_match",
        false,
        "generated plugin projection could not be derived: #{reason}"
      ),
      SuiteSupport.check(
        "#{connector_id}.generated.plugin.subscriptions_match",
        false,
        "generated plugin projection could not be derived: #{reason}"
      )
    ]
  end

  defp expected_action_modules(projected_operations, connector_module) do
    Enum.map(projected_operations, &ConsumerProjection.action_module(connector_module, &1))
  end

  defp expected_subscriptions(projected_triggers, connector_module) do
    projected_triggers
    |> Enum.map(&ConsumerProjection.sensor_module(connector_module, &1))
    |> Enum.map(&{&1, %{}})
  end

  defp plugin_exports do
    [
      {:generated_plugin_projection, 0},
      {:name, 0},
      {:state_key, 0},
      {:config_schema, 0},
      {:actions, 0},
      {:manifest, 0},
      {:plugin_spec, 1},
      {:subscriptions, 0},
      {:subscriptions, 2}
    ]
  end
end
