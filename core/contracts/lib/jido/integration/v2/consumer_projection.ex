defmodule Jido.Integration.V2.ConsumerProjection do
  @moduledoc """
  Shared projection rules for generated consumer surfaces built from authored
  manifests.

  Only authored entries marked `consumer_surface.mode == :common` project into
  generated actions, sensors, and plugins. Connector-local inventory remains
  authored runtime truth, but it stays outside the shared generated consumer
  surface until a connector author explicitly opts it in.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.InvocationRequest
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.Schema
  alias Jido.Integration.V2.TriggerSpec
  alias Jido.Signal

  @default_invoker :"Elixir.Jido.Integration.V2"

  defmodule ActionProjection do
    @moduledoc """
    Projected metadata for a generated `Jido.Action` surface.
    """

    alias Jido.Integration.V2.Contracts
    alias Jido.Integration.V2.Schema

    @schema Zoi.struct(
              __MODULE__,
              %{
                connector_module: Contracts.module_schema("action_projection.connector_module"),
                plugin_module: Contracts.module_schema("action_projection.plugin_module"),
                module: Contracts.module_schema("action_projection.module"),
                operation_id: Contracts.non_empty_string_schema("action_projection.operation_id"),
                normalized_id:
                  Contracts.non_empty_string_schema("action_projection.normalized_id"),
                action_name: Contracts.non_empty_string_schema("action_projection.action_name"),
                description: Contracts.non_empty_string_schema("action_projection.description"),
                category: Contracts.non_empty_string_schema("action_projection.category"),
                tags: Contracts.string_list_schema("action_projection.tags"),
                schema: Contracts.zoi_schema_schema("action_projection.schema"),
                output_schema: Contracts.zoi_schema_schema("action_projection.output_schema")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @spec schema() :: Zoi.schema()
    def schema, do: @schema

    @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
    def new(%__MODULE__{} = projection), do: {:ok, projection}
    def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

    @spec new!(map() | keyword() | t()) :: t()
    def new!(%__MODULE__{} = projection), do: projection
    def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)
  end

  defmodule PluginProjection do
    @moduledoc """
    Projected metadata for a generated `Jido.Plugin` bundle.
    """

    alias Jido.Integration.V2.Contracts
    alias Jido.Integration.V2.Schema

    @schema Zoi.struct(
              __MODULE__,
              %{
                connector_module: Contracts.module_schema("plugin_projection.connector_module"),
                module: Contracts.module_schema("plugin_projection.module"),
                name: Contracts.non_empty_string_schema("plugin_projection.name"),
                state_key: Contracts.atomish_schema("plugin_projection.state_key"),
                description: Contracts.non_empty_string_schema("plugin_projection.description"),
                category: Contracts.non_empty_string_schema("plugin_projection.category"),
                tags: Contracts.string_list_schema("plugin_projection.tags"),
                config_schema: Contracts.zoi_schema_schema("plugin_projection.config_schema"),
                actions: Zoi.list(Contracts.module_schema("plugin_projection.actions"))
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @spec schema() :: Zoi.schema()
    def schema, do: @schema

    @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
    def new(%__MODULE__{} = projection), do: {:ok, projection}
    def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

    @spec new!(map() | keyword() | t()) :: t()
    def new!(%__MODULE__{} = projection), do: projection
    def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)
  end

  defmodule SensorProjection do
    @moduledoc """
    Projected metadata for a generated `Jido.Sensor` surface.
    """

    alias Jido.Integration.V2.Contracts
    alias Jido.Integration.V2.Schema

    @schema Zoi.struct(
              __MODULE__,
              %{
                connector_id: Contracts.non_empty_string_schema("sensor_projection.connector_id"),
                connector_module: Contracts.module_schema("sensor_projection.connector_module"),
                plugin_module: Contracts.module_schema("sensor_projection.plugin_module"),
                module: Contracts.module_schema("sensor_projection.module"),
                trigger_id: Contracts.non_empty_string_schema("sensor_projection.trigger_id"),
                normalized_id:
                  Contracts.non_empty_string_schema("sensor_projection.normalized_id"),
                delivery_mode:
                  Contracts.enumish_schema([:poll, :webhook], "sensor_projection.delivery_mode"),
                auth_binding_kind:
                  Contracts.enumish_schema(
                    [:connection_id, :tenant, :none],
                    "sensor_projection.auth_binding_kind"
                  ),
                sensor_name: Contracts.non_empty_string_schema("sensor_projection.sensor_name"),
                jido_name: Contracts.non_empty_string_schema("sensor_projection.jido_name"),
                description: Contracts.non_empty_string_schema("sensor_projection.description"),
                category: Contracts.non_empty_string_schema("sensor_projection.category"),
                tags: Contracts.string_list_schema("sensor_projection.tags"),
                config_schema: Contracts.zoi_schema_schema("sensor_projection.config_schema"),
                sensor_schema: Contracts.zoi_schema_schema("sensor_projection.sensor_schema"),
                signal_schema: Contracts.zoi_schema_schema("sensor_projection.signal_schema"),
                signal_type: Contracts.non_empty_string_schema("sensor_projection.signal_type"),
                signal_source:
                  Contracts.non_empty_string_schema("sensor_projection.signal_source"),
                checkpoint: Contracts.any_map_schema(),
                polling: Contracts.any_map_schema()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @spec schema() :: Zoi.schema()
    def schema, do: @schema

    @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
    def new(%__MODULE__{} = projection), do: {:ok, projection}
    def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

    @spec new!(map() | keyword() | t()) :: t()
    def new!(%__MODULE__{} = projection), do: projection
    def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)
  end

  @spec action_projection!(module(), String.t()) :: ActionProjection.t()
  def action_projection!(connector_module, operation_id)
      when is_atom(connector_module) and is_binary(operation_id) do
    manifest = fetch_manifest!(connector_module)
    operation = fetch_projected_operation!(manifest, operation_id)

    ActionProjection.new!(%{
      connector_module: connector_module,
      plugin_module: plugin_module(connector_module),
      module: action_module(connector_module, operation),
      operation_id: operation.operation_id,
      normalized_id: OperationSpec.normalized_surface_id(operation),
      action_name: action_name(operation),
      description: operation.description || "Generated action for #{operation.operation_id}",
      category: manifest.catalog.category,
      tags: action_tags(manifest, operation),
      schema: operation.input_schema,
      output_schema: operation.output_schema
    })
  end

  @spec plugin_projection!(module()) :: PluginProjection.t()
  def plugin_projection!(connector_module) when is_atom(connector_module) do
    manifest = fetch_manifest!(connector_module)

    PluginProjection.new!(%{
      connector_module: connector_module,
      module: plugin_module(connector_module),
      name: plugin_name(manifest),
      state_key: plugin_state_key(manifest),
      description: "Generated plugin bundle for #{manifest.catalog.display_name}",
      category: manifest.catalog.category,
      tags: plugin_tags(manifest),
      config_schema: plugin_config_schema(manifest),
      actions: action_modules(connector_module)
    })
  end

  @spec sensor_projection!(module(), String.t()) :: SensorProjection.t()
  def sensor_projection!(connector_module, trigger_id)
      when is_atom(connector_module) and is_binary(trigger_id) do
    manifest = fetch_manifest!(connector_module)
    trigger = fetch_projected_trigger!(manifest, trigger_id)

    SensorProjection.new!(%{
      connector_id: manifest.connector,
      connector_module: connector_module,
      plugin_module: plugin_module(connector_module),
      module: sensor_module(connector_module, trigger),
      trigger_id: trigger.trigger_id,
      normalized_id: TriggerSpec.normalized_surface_id(trigger),
      delivery_mode: trigger.delivery_mode,
      auth_binding_kind: manifest.auth.binding_kind,
      sensor_name: sensor_name(trigger),
      jido_name: jido_sensor_name(trigger),
      description: trigger.description || "Generated sensor for #{trigger.trigger_id}",
      category: manifest.catalog.category,
      tags: sensor_tags(manifest, trigger),
      config_schema: trigger.config_schema,
      sensor_schema: sensor_runtime_schema(manifest, trigger),
      signal_schema: trigger.signal_schema,
      signal_type: sensor_signal_type(trigger),
      signal_source: sensor_signal_source(trigger),
      checkpoint: trigger.checkpoint,
      polling: TriggerSpec.polling(trigger) || %{}
    })
  end

  @spec action_module(module(), String.t() | OperationSpec.t()) :: module()
  def action_module(connector_module, operation_id_or_spec)

  def action_module(connector_module, %OperationSpec{} = operation)
      when is_atom(connector_module) do
    Module.concat([
      connector_module,
      Generated,
      Actions,
      operation |> action_name() |> Macro.camelize()
    ])
  end

  def action_module(connector_module, operation_id) when is_atom(connector_module) do
    connector_module
    |> fetch_manifest!()
    |> fetch_projected_operation!(operation_id)
    |> then(&action_module(connector_module, &1))
  end

  @spec action_modules(module()) :: [module()]
  def action_modules(connector_module) when is_atom(connector_module) do
    connector_module
    |> fetch_manifest!()
    |> projected_operations()
    |> Enum.map(&action_module(connector_module, &1))
  end

  @spec sensor_module(module(), String.t() | TriggerSpec.t()) :: module()
  def sensor_module(connector_module, trigger_id_or_spec)

  def sensor_module(connector_module, %TriggerSpec{} = trigger)
      when is_atom(connector_module) do
    Module.concat([
      connector_module,
      Generated,
      Sensors,
      trigger |> sensor_name() |> Macro.camelize()
    ])
  end

  def sensor_module(connector_module, trigger_id) when is_atom(connector_module) do
    connector_module
    |> fetch_manifest!()
    |> fetch_projected_trigger!(trigger_id)
    |> then(&sensor_module(connector_module, &1))
  end

  @spec sensor_modules(module()) :: [module()]
  def sensor_modules(connector_module) when is_atom(connector_module) do
    connector_module
    |> fetch_manifest!()
    |> projected_triggers()
    |> Enum.map(&sensor_module(connector_module, &1))
  end

  @spec projected_operations(Manifest.t()) :: [OperationSpec.t()]
  def projected_operations(%Manifest{} = manifest) do
    Enum.filter(manifest.operations, &OperationSpec.common_consumer_surface?/1)
  end

  @spec projected_triggers(Manifest.t()) :: [TriggerSpec.t()]
  def projected_triggers(%Manifest{} = manifest) do
    Enum.filter(manifest.triggers, &TriggerSpec.common_consumer_surface?/1)
  end

  @spec plugin_module(module()) :: module()
  def plugin_module(connector_module) when is_atom(connector_module) do
    Module.concat([connector_module, Generated, Plugin])
  end

  @spec action_opts(ActionProjection.t()) :: keyword()
  def action_opts(%ActionProjection{} = projection) do
    [
      name: projection.action_name,
      description: projection.description,
      category: projection.category,
      tags: projection.tags,
      schema: projection.schema,
      output_schema: projection.output_schema
    ]
  end

  @spec sensor_opts(SensorProjection.t()) :: keyword()
  def sensor_opts(%SensorProjection{} = projection) do
    [
      name: projection.jido_name,
      description: projection.description,
      schema: projection.sensor_schema
    ]
  end

  @spec plugin_opts(PluginProjection.t()) :: keyword()
  def plugin_opts(%PluginProjection{} = projection) do
    [
      name: projection.name,
      state_key: projection.state_key,
      actions: projection.actions,
      description: projection.description,
      category: projection.category,
      tags: projection.tags,
      config_schema: projection.config_schema,
      signal_patterns: plugin_signal_patterns(projection),
      subscriptions: plugin_subscriptions(projection)
    ]
  end

  @spec filtered_actions!(PluginProjection.t(), map()) :: [module()]
  def filtered_actions!(%PluginProjection{actions: actions}, config) when is_map(config) do
    enabled_actions =
      config
      |> Contracts.get(:enabled_actions, [])
      |> Contracts.normalize_string_list!("plugin.enabled_actions")

    if enabled_actions == [] do
      actions
    else
      filter_actions!(actions, enabled_actions)
    end
  end

  @doc false
  @spec invocation_request!(ActionProjection.t(), map(), map()) :: InvocationRequest.t()
  def invocation_request!(%ActionProjection{} = projection, params, context)
      when is_map(params) and is_map(context) do
    invoke_context = invoke_context(context)

    %{
      capability_id: projection.operation_id,
      input: Map.drop(params, [:connection_id, "connection_id"]),
      connection_id: resolve_connection_id(projection, params, context, invoke_context),
      actor_id: read_invoke_value(invoke_context, context, :actor_id),
      tenant_id: read_invoke_value(invoke_context, context, :tenant_id),
      environment: read_invoke_value(invoke_context, context, :environment),
      trace_id: read_invoke_value(invoke_context, context, :trace_id),
      allowed_operations: read_invoke_value(invoke_context, context, :allowed_operations),
      sandbox: read_invoke_value(invoke_context, context, :sandbox),
      target_id: read_invoke_value(invoke_context, context, :target_id),
      aggregator_id: read_invoke_value(invoke_context, context, :aggregator_id),
      aggregator_epoch: read_invoke_value(invoke_context, context, :aggregator_epoch),
      extensions: read_invoke_value(invoke_context, context, :extensions, [])
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> InvocationRequest.new!()
  end

  def invocation_request!(%ActionProjection{}, params, context) do
    raise ArgumentError,
          "generated actions expect params and context maps, got: #{inspect({params, context})}"
  end

  @spec run_action(ActionProjection.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run_action(%ActionProjection{} = projection, params, context)
      when is_map(params) and is_map(context) do
    request = invocation_request!(projection, params, context)

    case invoke(request) do
      {:ok, %{output: output}} when is_map(output) ->
        {:ok, output}

      {:ok, response} ->
        {:error, {:invalid_invoke_response, response}}

      {:error, _reason} = error ->
        error
    end
  end

  def run_action(%ActionProjection{}, params, context) do
    raise ArgumentError,
          "generated actions expect params and context maps, got: #{inspect({params, context})}"
  end

  @spec init_sensor(SensorProjection.t(), map(), map()) :: {:ok, map()}
  def init_sensor(%SensorProjection{} = projection, config, context)
      when is_map(config) and is_map(context) do
    {:ok, %{projection: projection, config: config, context: context}}
  end

  def init_sensor(%SensorProjection{}, config, context) do
    raise ArgumentError,
          "generated sensors expect config and context maps, got: #{inspect({config, context})}"
  end

  @spec handle_sensor_event(SensorProjection.t(), term(), map()) ::
          {:ok, map()} | {:ok, map(), [{:emit, Signal.t()}]}
  def handle_sensor_event(%SensorProjection{} = projection, event, state) when is_map(state) do
    case extract_sensor_payload(event) do
      {:ok, payload} ->
        {:ok, state, [{:emit, sensor_signal!(projection, payload)}]}

      :ignore ->
        {:ok, state}
    end
  end

  def handle_sensor_event(%SensorProjection{}, event, state) do
    raise ArgumentError,
          "generated sensors expect a state map, got: #{inspect({event, state})}"
  end

  @spec sensor_signal!(SensorProjection.t(), term()) :: Signal.t()
  def sensor_signal!(%SensorProjection{} = projection, payload) do
    payload =
      case Zoi.parse(projection.signal_schema, payload) do
        {:ok, validated_payload} ->
          validated_payload

        {:error, errors} ->
          raise ArgumentError,
                "generated sensor #{inspect(projection.module)} received invalid signal payload: #{inspect(errors)}"
      end

    Signal.new!(projection.signal_type, payload, source: projection.signal_source)
  end

  @spec plugin_subscriptions(PluginProjection.t()) :: [{module(), map()}]
  def plugin_subscriptions(%PluginProjection{} = projection) do
    projection
    |> projected_sensor_projections()
    |> Enum.map(&subscription_tuple/1)
  end

  defp fetch_manifest!(connector_module) do
    manifest = connector_module.manifest()

    if match?(%Manifest{}, manifest) do
      validate_generated_consumer_projections!(connector_module, manifest)
      manifest
    else
      raise ArgumentError,
            "connector module #{inspect(connector_module)} must return a manifest, got: #{inspect(manifest)}"
    end
  end

  defp validate_generated_consumer_projections!(connector_module, %Manifest{} = manifest) do
    validate_generated_action_projections!(connector_module, manifest)
    validate_generated_trigger_projections!(connector_module, manifest)
  end

  defp validate_generated_action_projections!(connector_module, %Manifest{} = manifest) do
    operations = projected_operations(manifest)

    duplicate_modules =
      operations
      |> Enum.map(&action_module(connector_module, &1))
      |> duplicate_values()

    duplicate_action_names =
      operations
      |> Enum.map(&action_name/1)
      |> duplicate_values()

    if duplicate_modules == [] and duplicate_action_names == [] do
      :ok
    else
      details =
        []
        |> append_duplicate_detail("modules", duplicate_modules)
        |> append_duplicate_detail("action names", duplicate_action_names)
        |> Enum.join(", ")

      raise ArgumentError,
            "generated consumer action projections must be unique within a connector, duplicate #{details}"
    end
  end

  defp validate_generated_trigger_projections!(connector_module, %Manifest{} = manifest) do
    triggers = projected_triggers(manifest)

    duplicate_modules =
      triggers
      |> Enum.map(&sensor_module(connector_module, &1))
      |> duplicate_values()

    duplicate_sensor_names =
      triggers
      |> Enum.map(&sensor_name/1)
      |> duplicate_values()

    duplicate_jido_sensor_names =
      triggers
      |> Enum.map(&jido_sensor_name/1)
      |> duplicate_values()

    if duplicate_modules == [] and duplicate_sensor_names == [] and
         duplicate_jido_sensor_names == [] do
      :ok
    else
      details =
        []
        |> append_duplicate_detail("modules", duplicate_modules)
        |> append_duplicate_detail("sensor names", duplicate_sensor_names)
        |> append_duplicate_detail("Jido sensor names", duplicate_jido_sensor_names)
        |> Enum.join(", ")

      raise ArgumentError,
            "generated consumer trigger projections must be unique within a connector, duplicate #{details}"
    end
  end

  defp fetch_projected_operation!(manifest, operation_id) do
    case Manifest.fetch_operation(manifest, operation_id) do
      %OperationSpec{} = operation ->
        if OperationSpec.common_consumer_surface?(operation) do
          operation
        else
          raise ArgumentError,
                "operation #{inspect(operation_id)} is not projected into the common consumer surface"
        end

      nil ->
        raise ArgumentError, "unknown authored operation #{inspect(operation_id)}"
    end
  end

  defp fetch_projected_trigger!(manifest, trigger_id) do
    case Manifest.fetch_trigger(manifest, trigger_id) do
      %TriggerSpec{} = trigger ->
        if TriggerSpec.common_consumer_surface?(trigger) do
          trigger
        else
          raise ArgumentError,
                "trigger #{inspect(trigger_id)} is not projected into the common consumer surface"
        end

      nil ->
        raise ArgumentError, "unknown authored trigger #{inspect(trigger_id)}"
    end
  end

  defp action_name(%OperationSpec{} = operation) do
    operation
    |> OperationSpec.action_name()
    |> Contracts.validate_non_empty_string!("operation.consumer_surface.action_name")
  end

  defp sensor_name(%TriggerSpec{} = trigger) do
    trigger
    |> TriggerSpec.sensor_name()
    |> Contracts.validate_non_empty_string!("trigger.consumer_surface.sensor_name")
  end

  defp jido_sensor_name(%TriggerSpec{} = trigger) do
    trigger
    |> TriggerSpec.jido_sensor_name()
    |> Contracts.validate_non_empty_string!("trigger.jido.sensor.name")
  end

  defp sensor_signal_type(%TriggerSpec{} = trigger) do
    trigger
    |> TriggerSpec.sensor_signal_type()
    |> Contracts.validate_non_empty_string!("trigger.jido.sensor.signal_type")
  end

  defp sensor_signal_source(%TriggerSpec{} = trigger) do
    trigger
    |> TriggerSpec.sensor_signal_source()
    |> Contracts.validate_non_empty_string!("trigger.jido.sensor.signal_source")
  end

  defp action_tags(manifest, operation) do
    manifest.catalog.tags
    |> Kernel.++([manifest.connector, Atom.to_string(operation.runtime_class)])
    |> Enum.uniq()
  end

  defp sensor_tags(manifest, trigger) do
    manifest.catalog.tags
    |> Kernel.++([manifest.connector, Atom.to_string(trigger.delivery_mode)])
    |> Enum.uniq()
  end

  defp plugin_name(manifest), do: normalize_identifier(manifest.connector)

  defp plugin_signal_patterns(%PluginProjection{connector_module: connector_module}) do
    connector_module
    |> fetch_manifest!()
    |> projected_triggers()
    |> Enum.map(&sensor_signal_type/1)
  end

  defp plugin_state_key(manifest) do
    manifest.connector
    |> normalize_identifier()
    |> String.to_atom()
  end

  defp plugin_tags(manifest) do
    manifest.catalog.tags
    |> Kernel.++([manifest.connector, "generated"])
    |> Enum.uniq()
  end

  defp plugin_config_schema(%Manifest{} = manifest) do
    connection_id_schema =
      Zoi.string(description: "Durable connection_id binding for generated connector actions")

    connection_id_schema =
      case manifest.auth.binding_kind do
        :connection_id -> connection_id_schema
        _other -> connection_id_schema |> Zoi.optional()
      end

    Contracts.ordered_object!(
      connection_id: connection_id_schema,
      invoke_defaults:
        Contracts.ordered_object!(
          tenant_id:
            Zoi.string(description: "Tenant id for generated trigger and action invokes")
            |> Zoi.optional(),
          actor_id:
            Zoi.string(description: "Actor id for generated trigger and action invokes")
            |> Zoi.optional(),
          environment:
            Zoi.atom(
              description: "Execution environment for generated trigger and action invokes"
            )
            |> Zoi.default(:prod),
          target_id:
            Zoi.string(description: "Optional target id for generated invokes") |> Zoi.optional(),
          sandbox: Zoi.map(description: "Optional sandbox posture override") |> Zoi.optional(),
          extensions:
            Zoi.map(description: "Optional invoke extensions for generated triggers and actions")
            |> Zoi.default(%{})
        )
        |> Zoi.default(%{}),
      trigger_subscriptions: trigger_subscriptions_schema(manifest),
      enabled_actions:
        Zoi.list(Zoi.string(), description: "Optional subset of generated actions to enable")
        |> Zoi.default([])
    )
  end

  defp trigger_subscriptions_schema(%Manifest{} = manifest) do
    fields =
      manifest
      |> projected_triggers()
      |> Enum.filter(&(&1.delivery_mode == :poll))
      |> Enum.map(fn trigger ->
        {String.to_atom(sensor_name(trigger)), trigger_subscription_schema(trigger)}
      end)

    Contracts.ordered_object!(fields)
    |> Zoi.default(%{})
  end

  defp trigger_subscription_schema(%TriggerSpec{} = trigger) do
    default_interval_ms = TriggerSpec.polling_default_interval_ms(trigger) || 60_000
    min_interval_ms = TriggerSpec.polling_min_interval_ms(trigger) || default_interval_ms

    Contracts.ordered_object!(
      enabled:
        Zoi.boolean(description: "Enable this generated poll subscription") |> Zoi.default(false),
      interval_ms:
        Zoi.integer(description: "Polling interval in milliseconds")
        |> Zoi.refine({__MODULE__, :validate_min_interval, [min_interval_ms]})
        |> Zoi.default(default_interval_ms),
      partition_key:
        Zoi.string(
          description: "Stable checkpoint partition key for this generated poll subscription"
        )
        |> Zoi.optional(),
      config:
        trigger.config_schema
        |> Zoi.optional()
    )
  end

  @doc false
  @spec validate_min_interval(integer(), [pos_integer()], keyword()) :: :ok | {:error, String.t()}
  def validate_min_interval(value, [min_interval_ms], _opts)
      when is_integer(value) and is_integer(min_interval_ms) do
    if value >= min_interval_ms do
      :ok
    else
      {:error, "must be greater than or equal to #{min_interval_ms}"}
    end
  end

  def validate_min_interval(_value, _args, _opts), do: :ok

  defp sensor_runtime_schema(%Manifest{}, %TriggerSpec{delivery_mode: :webhook} = trigger) do
    trigger.config_schema
  end

  defp sensor_runtime_schema(%Manifest{} = manifest, %TriggerSpec{delivery_mode: :poll} = trigger) do
    default_interval_ms = TriggerSpec.polling_default_interval_ms(trigger) || 60_000
    min_interval_ms = TriggerSpec.polling_min_interval_ms(trigger) || default_interval_ms

    base_fields =
      [
        interval_ms:
          Zoi.integer(description: "Polling interval in milliseconds")
          |> Zoi.refine({__MODULE__, :validate_min_interval, [min_interval_ms]})
          |> Zoi.default(default_interval_ms),
        tenant_id: Zoi.string(description: "Tenant id used for checkpoint and trigger admission"),
        actor_id:
          Zoi.string(description: "Actor id used for generated poll invokes")
          |> Zoi.optional(),
        environment:
          Zoi.atom(description: "Execution environment used for generated poll invokes")
          |> Zoi.default(:prod),
        target_id:
          Zoi.string(description: "Optional target id for generated poll invokes")
          |> Zoi.optional(),
        sandbox:
          Zoi.map(description: "Optional sandbox posture override for generated poll invokes")
          |> Zoi.optional(),
        partition_key: partition_key_schema(trigger),
        config:
          trigger.config_schema
          |> Zoi.optional(),
        extensions:
          Zoi.map(description: "Optional invoke extensions for generated poll invokes")
          |> Zoi.default(%{})
      ]

    fields =
      case manifest.auth.binding_kind do
        :connection_id ->
          [
            {:connection_id,
             Zoi.string(description: "Durable connection binding for generated poll invokes")}
            | base_fields
          ]

        _other ->
          base_fields
      end

    Contracts.ordered_object!(fields)
  end

  defp partition_key_schema(%TriggerSpec{} = trigger) do
    if present_string?(Contracts.get(trigger.checkpoint, :partition_key)) do
      Zoi.string(description: "Stable checkpoint partition key")
      |> Zoi.optional()
    else
      Zoi.string(description: "Stable checkpoint partition key")
      |> Zoi.optional()
    end
  end

  defp projected_sensor_projections(%PluginProjection{connector_module: connector_module}) do
    connector_module
    |> fetch_manifest!()
    |> projected_triggers()
    |> Enum.map(&sensor_projection!(connector_module, &1.trigger_id))
  end

  defp subscription_tuple(%SensorProjection{} = projection), do: {projection.module, %{}}

  defp extract_sensor_payload({:emit, payload}), do: {:ok, payload}
  defp extract_sensor_payload({:signal, payload}), do: {:ok, payload}
  defp extract_sensor_payload(%{} = payload), do: {:ok, payload}
  defp extract_sensor_payload(_event), do: :ignore

  defp normalize_identifier(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> Contracts.validate_non_empty_string!("generated consumer identifier")
  end

  defp filter_actions!(actions, enabled_actions) do
    unknown_actions =
      Enum.reject(enabled_actions, fn enabled_action ->
        Enum.any?(actions, fn action ->
          enabled_action in action_identifiers(action)
        end)
      end)

    if unknown_actions != [] do
      raise ArgumentError,
            "enabled_actions contains unknown generated actions: #{inspect(unknown_actions)}"
    end

    Enum.map(enabled_actions, fn enabled_action ->
      Enum.find(actions, fn action ->
        enabled_action in action_identifiers(action)
      end)
    end)
  end

  defp action_identifiers(action) do
    [
      safe_action_identifier(action, :name),
      safe_action_identifier(action, :operation_id),
      inspect(action)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp safe_action_identifier(action, function_name) do
    if match?({:module, _module}, Code.ensure_compiled(action)) and
         function_exported?(action, function_name, 0) do
      apply(action, function_name, [])
    end
  end

  defp duplicate_values(values) do
    values
    |> Enum.frequencies()
    |> Enum.filter(fn {_value, count} -> count > 1 end)
    |> Enum.map(fn {value, _count} -> value end)
    |> Enum.sort()
  end

  defp append_duplicate_detail(details, _label, []), do: details

  defp append_duplicate_detail(details, label, values) do
    details ++ ["#{label} #{inspect(values)}"]
  end

  defp invoke_context(context) do
    case Contracts.get(context, :invoke, %{}) do
      %{} = invoke_context ->
        invoke_context

      nil ->
        %{}

      other ->
        raise ArgumentError, "action context invoke entry must be a map, got: #{inspect(other)}"
    end
  end

  defp read_invoke_value(invoke_context, context, key, default \\ nil) do
    Contracts.get(invoke_context, key, Contracts.get(context, key, default))
  end

  defp resolve_connection_id(projection, params, context, invoke_context) do
    [
      Contracts.get(params, :connection_id),
      read_invoke_value(invoke_context, context, :connection_id),
      connection_id_from_map(Contracts.get(context, :plugin_config, %{})),
      connection_id_from_map(Contracts.get(context, :config, %{})),
      connection_id_from_plugin_spec(Contracts.get(context, :plugin_spec)),
      connection_id_from_agent_config(projection, context, invoke_context)
    ]
    |> Enum.find(&present_string?/1)
  end

  defp connection_id_from_plugin_spec(%{config: config}) when is_map(config),
    do: connection_id_from_map(config)

  defp connection_id_from_plugin_spec(_other), do: nil

  defp connection_id_from_agent_config(projection, context, invoke_context) do
    agent_module = read_invoke_value(invoke_context, context, :agent_module)

    if is_atom(agent_module) and function_exported?(agent_module, :plugin_config, 1) do
      agent_module
      |> then(& &1.plugin_config(projection.plugin_module))
      |> then(&connection_id_from_map(&1 || %{}))
    end
  rescue
    _error -> nil
  end

  defp connection_id_from_map(%{} = config), do: Contracts.get(config, :connection_id)
  defp connection_id_from_map(_other), do: nil

  defp present_string?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0

  defp invoke(request) do
    if function_exported?(@default_invoker, :invoke, 1) do
      :erlang.apply(@default_invoker, :invoke, [request])
    else
      {:error, {:invalid_invoker, @default_invoker}}
    end
  end
end
