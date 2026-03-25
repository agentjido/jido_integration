defmodule Jido.Integration.V2.ConsumerSurfaceRuntime do
  @moduledoc false

  require Logger

  alias Jido.Integration.V2
  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.Ingress
  alias Jido.Integration.V2.Ingress.Definition
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord
  alias Jido.Integration.V2.TriggerSpec

  @default_request_invoker V2
  @default_capability_invoker V2
  @default_control_plane ControlPlane
  @default_ingress Ingress

  @spec run_action(ConsumerProjection.ActionProjection.t(), map(), map()) ::
          {:ok, map()} | {:error, term()}
  def run_action(%ConsumerProjection.ActionProjection{} = projection, params, context)
      when is_map(params) and is_map(context) do
    request = ConsumerProjection.invocation_request!(projection, params, context)
    request_invoker = runtime_module(context, :request_invoker, @default_request_invoker)

    case invoke_request(request_invoker, request) do
      {:ok, %{output: output}} when is_map(output) ->
        {:ok, output}

      {:ok, response} ->
        {:error, {:invalid_invoke_response, response}}

      {:error, _reason} = error ->
        error
    end
  end

  def run_action(%ConsumerProjection.ActionProjection{}, params, context) do
    raise ArgumentError,
          "generated actions expect params and context maps, got: #{inspect({params, context})}"
  end

  @spec init_sensor(ConsumerProjection.SensorProjection.t(), map(), map()) ::
          {:ok, map()} | {:ok, map(), [Jido.Sensor.sensor_directive()]}
  def init_sensor(%ConsumerProjection.SensorProjection{} = projection, config, context)
      when is_map(config) and is_map(context) do
    state = %{projection: projection, config: config, context: context}

    case projection.delivery_mode do
      :poll ->
        {:ok, state, [{:schedule, config.interval_ms}]}

      :webhook ->
        {:ok, state}
    end
  end

  def init_sensor(%ConsumerProjection.SensorProjection{}, config, context) do
    raise ArgumentError,
          "generated sensors expect config and context maps, got: #{inspect({config, context})}"
  end

  @spec handle_sensor_event(ConsumerProjection.SensorProjection.t(), term(), map()) ::
          {:ok, map()} | {:ok, map(), [Jido.Sensor.sensor_directive()]}
  def handle_sensor_event(
        %ConsumerProjection.SensorProjection{delivery_mode: :poll} = projection,
        :tick,
        state
      )
      when is_map(state) do
    case poll_once(projection, state) do
      {:ok, signals, next_state} ->
        directives = Enum.map(signals, &{:emit, &1}) ++ [{:schedule, state.config.interval_ms}]
        {:ok, next_state, directives}

      {:error, reason, next_state} ->
        Logger.warning(
          "Generated poll sensor #{inspect(projection.module)} poll tick failed: #{inspect(reason)}"
        )

        {:ok, next_state, [{:schedule, state.config.interval_ms}]}
    end
  end

  def handle_sensor_event(%ConsumerProjection.SensorProjection{} = projection, event, state)
      when is_map(state) do
    case extract_sensor_payload(event) do
      {:ok, payload} ->
        {:ok, state, [{:emit, ConsumerProjection.sensor_signal!(projection, payload)}]}

      :ignore ->
        {:ok, state}
    end
  end

  def handle_sensor_event(%ConsumerProjection.SensorProjection{}, event, state) do
    raise ArgumentError,
          "generated sensors expect a state map, got: #{inspect({event, state})}"
  end

  @spec plugin_subscriptions(ConsumerProjection.PluginProjection.t(), map(), map()) ::
          [{module(), map()}]
  def plugin_subscriptions(%ConsumerProjection.PluginProjection{} = projection, config, context)
      when is_map(config) and is_map(context) do
    manifest = projection.connector_module.manifest()
    invoke_defaults = Contracts.get(config, :invoke_defaults, %{})
    trigger_subscriptions = Contracts.get(config, :trigger_subscriptions, %{})

    manifest
    |> ConsumerProjection.projected_triggers()
    |> Enum.filter(&(&1.delivery_mode == :poll))
    |> Enum.reduce([], fn trigger, acc ->
      sensor_projection =
        ConsumerProjection.sensor_projection!(projection.connector_module, trigger.trigger_id)

      subscription_key = String.to_atom(sensor_projection.sensor_name)
      subscription_config = lookup_subscription(trigger_subscriptions, subscription_key)

      if subscription_enabled?(subscription_config) do
        sensor_config =
          build_sensor_config(
            sensor_projection,
            trigger,
            config,
            invoke_defaults,
            subscription_config
          )

        acc ++ [{sensor_projection.module, sensor_config}]
      else
        acc
      end
    end)
  end

  def plugin_subscriptions(%ConsumerProjection.PluginProjection{}, config, context) do
    raise ArgumentError,
          "generated plugins expect config and context maps for subscriptions/2, got: #{inspect({config, context})}"
  end

  @spec webhook_signal!(module(), String.t(), map()) :: Jido.Signal.t()
  def webhook_signal!(connector_module, trigger_id, payload)
      when is_atom(connector_module) and is_binary(trigger_id) and is_map(payload) do
    projection = ConsumerProjection.sensor_projection!(connector_module, trigger_id)
    ConsumerProjection.sensor_signal!(projection, payload)
  end

  @spec webhook_signal!(module(), TriggerRecord.t()) :: Jido.Signal.t()
  def webhook_signal!(connector_module, %TriggerRecord{} = trigger)
      when is_atom(connector_module) do
    webhook_signal!(connector_module, trigger.trigger_id, trigger.payload)
  end

  defp poll_once(projection, %{config: config, context: context} = state) do
    tenant_id = required_string!(config, :tenant_id, "generated poll sensor tenant_id")
    partition_key = resolve_partition_key!(projection, config)
    checkpoint_cursor = checkpoint_cursor(context, projection, tenant_id, partition_key)

    input =
      config
      |> Contracts.get(:config, %{})
      |> Map.new()
      |> maybe_put_checkpoint_cursor(checkpoint_cursor)

    invoke_opts = invoke_opts(projection, config)
    capability_invoker = runtime_module(context, :capability_invoker, @default_capability_invoker)

    case invoke_capability(capability_invoker, projection.trigger_id, input, invoke_opts) do
      {:ok, %{output: output}} when is_map(output) ->
        emit_signals = admit_signals(context, projection, tenant_id, partition_key, output)

        case maybe_put_checkpoint(
               context,
               projection,
               tenant_id,
               partition_key,
               output,
               emit_signals
             ) do
          :ok ->
            {:ok, emit_signals, state}

          {:error, reason} ->
            {:error, reason, state}
        end

      {:ok, response} ->
        {:error, {:invalid_invoke_response, response}, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp admit_signals(context, projection, tenant_id, partition_key, output) do
    ingress = runtime_module(context, :ingress, @default_ingress)
    definition = poll_definition!(projection)
    checkpoint_cursor = output_cursor!(projection, output)
    checkpoint_time = output_last_event_time(output, checkpoint_cursor)
    dedupe_keys = output_dedupe_keys(output)
    checkpoint_event_id = List.first(dedupe_keys)

    output
    |> output_signals()
    |> Enum.with_index()
    |> Enum.reduce([], fn {payload, index}, acc ->
      request = %{
        tenant_id: tenant_id,
        partition_key: partition_key,
        cursor: checkpoint_cursor,
        event: payload,
        external_id: Enum.at(dedupe_keys, index),
        last_event_id: checkpoint_event_id,
        last_event_time: checkpoint_time
      }

      case ingress.admit_poll(request, definition) do
        {:ok, %{status: :accepted}} ->
          acc ++ [ConsumerProjection.sensor_signal!(projection, payload)]

        {:ok, %{status: :duplicate}} ->
          acc

        {:error, error} ->
          Logger.warning(
            "Generated poll sensor #{inspect(projection.module)} ingress admission failed: #{inspect(error)}"
          )

          acc
      end
    end)
  end

  defp maybe_put_checkpoint(
         _context,
         _projection,
         _tenant_id,
         _partition_key,
         _output,
         emit_signals
       )
       when emit_signals != [],
       do: :ok

  defp maybe_put_checkpoint(context, projection, tenant_id, partition_key, output, _emit_signals) do
    case output_checkpoint(output) do
      %{cursor: cursor} ->
        control_plane = runtime_module(context, :control_plane, @default_control_plane)

        if present_string?(cursor) do
          checkpoint =
            TriggerCheckpoint.new!(%{
              tenant_id: tenant_id,
              connector_id: projection.connector_id,
              trigger_id: projection.trigger_id,
              partition_key: partition_key,
              cursor: cursor,
              last_event_id: nil,
              last_event_time: output_last_event_time(output, cursor)
            })

          control_plane.put_trigger_checkpoint(checkpoint)
        else
          :ok
        end

      _other ->
        :ok
    end
  end

  defp build_sensor_config(
         sensor_projection,
         trigger,
         plugin_config,
         invoke_defaults,
         subscription_config
       ) do
    config = Contracts.get(subscription_config, :config, %{}) || %{}

    interval_ms =
      Contracts.get(
        subscription_config,
        :interval_ms,
        TriggerSpec.polling_default_interval_ms(trigger)
      )

    sensor_config =
      %{
        interval_ms: interval_ms,
        tenant_id: Contracts.get(invoke_defaults, :tenant_id),
        actor_id: Contracts.get(invoke_defaults, :actor_id),
        environment: Contracts.get(invoke_defaults, :environment, :prod),
        target_id: Contracts.get(invoke_defaults, :target_id),
        sandbox: Contracts.get(invoke_defaults, :sandbox),
        partition_key:
          Contracts.get(subscription_config, :partition_key) ||
            default_partition_key(sensor_projection, plugin_config),
        config: config,
        extensions: Contracts.get(invoke_defaults, :extensions, %{})
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    case sensor_projection.auth_binding_kind do
      :connection_id ->
        Map.put(sensor_config, :connection_id, Contracts.get(plugin_config, :connection_id))

      _other ->
        sensor_config
    end
  end

  defp invoke_request(invoker, request) do
    if function_exported?(invoker, :invoke, 1) do
      :erlang.apply(invoker, :invoke, [request])
    else
      {:error, {:invalid_invoker, invoker}}
    end
  end

  defp invoke_capability(invoker, capability_id, input, opts) do
    if function_exported?(invoker, :invoke, 3) do
      :erlang.apply(invoker, :invoke, [capability_id, input, opts])
    else
      {:error, {:invalid_capability_invoker, invoker}}
    end
  end

  defp invoke_opts(projection, config) do
    []
    |> maybe_put_opt(:connection_id, Contracts.get(config, :connection_id))
    |> maybe_put_opt(:actor_id, Contracts.get(config, :actor_id))
    |> maybe_put_opt(:tenant_id, Contracts.get(config, :tenant_id))
    |> maybe_put_opt(:environment, Contracts.get(config, :environment))
    |> maybe_put_opt(:allowed_operations, [projection.trigger_id])
    |> maybe_put_opt(:sandbox, Contracts.get(config, :sandbox))
    |> maybe_put_opt(:target_id, Contracts.get(config, :target_id))
    |> Kernel.++(normalize_extensions(Contracts.get(config, :extensions, %{})))
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp poll_definition!(projection) do
    manifest = projection.connector_module.manifest()

    trigger =
      manifest
      |> Manifest.fetch_trigger(projection.trigger_id)
      |> Kernel.||(
        raise ArgumentError,
              "generated poll sensor #{inspect(projection.module)} could not find trigger #{inspect(projection.trigger_id)}"
      )

    Definition.from_trigger!(projection.connector_id, trigger)
  end

  defp checkpoint_cursor(context, projection, tenant_id, partition_key) do
    control_plane = runtime_module(context, :control_plane, @default_control_plane)

    case control_plane.fetch_trigger_checkpoint(
           tenant_id,
           projection.connector_id,
           projection.trigger_id,
           partition_key
         ) do
      {:ok, checkpoint} -> checkpoint.cursor
      :error -> nil
    end
  end

  defp output_signals(output) do
    output
    |> Contracts.get(:signals, [])
    |> List.wrap()
  end

  defp output_dedupe_keys(output) do
    output
    |> Contracts.get(:dedupe_keys, [])
    |> List.wrap()
  end

  defp output_checkpoint(output) do
    Contracts.get(output, :checkpoint, %{}) || %{}
  end

  defp output_cursor!(projection, output) do
    case output_checkpoint(output) do
      %{cursor: cursor} when is_binary(cursor) ->
        if present_string?(cursor) do
          cursor
        else
          raise ArgumentError,
                "generated poll sensor #{inspect(projection.module)} expected output.checkpoint.cursor, got: #{inspect(%{cursor: cursor})}"
        end

      other ->
        raise ArgumentError,
              "generated poll sensor #{inspect(projection.module)} expected output.checkpoint.cursor, got: #{inspect(other)}"
    end
  end

  defp output_last_event_time(output, cursor) do
    case Contracts.get(output, :checkpoint, %{}) do
      %{last_event_time: last_event_time} -> normalize_datetime(last_event_time)
      _other -> normalize_datetime(cursor)
    end
  end

  defp normalize_datetime(%DateTime{} = value), do: value

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp lookup_subscription(trigger_subscriptions, key) when is_map(trigger_subscriptions) do
    Contracts.get(trigger_subscriptions, key, %{}) || %{}
  end

  defp subscription_enabled?(subscription_config) when is_map(subscription_config) do
    Contracts.get(subscription_config, :enabled, false) == true
  end

  defp default_partition_key(projection, plugin_config) do
    Contracts.get(plugin_config, :connection_id)
    |> case do
      value when is_binary(value) and projection.auth_binding_kind == :connection_id -> value
      _other -> nil
    end
  end

  defp resolve_partition_key!(projection, config) do
    case Contracts.get(config, :partition_key) || default_partition_key(projection, config) do
      value when is_binary(value) ->
        if present_string?(value) do
          value
        else
          raise ArgumentError,
                "generated poll sensor #{inspect(projection.module)} requires a partition_key or a connection_id-backed default"
        end

      _other ->
        raise ArgumentError,
              "generated poll sensor #{inspect(projection.module)} requires a partition_key or a connection_id-backed default"
    end
  end

  defp required_string!(config, key, label) do
    case Contracts.get(config, key) do
      value when is_binary(value) ->
        if present_string?(value) do
          value
        else
          raise ArgumentError, "#{label} is required"
        end

      _other ->
        raise ArgumentError, "#{label} is required"
    end
  end

  defp present_string?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0

  defp maybe_put_checkpoint_cursor(input, nil), do: input
  defp maybe_put_checkpoint_cursor(input, cursor), do: Map.put(input, :checkpoint_cursor, cursor)

  defp runtime_module(context, key, default) do
    context
    |> Contracts.get(:consumer_runtime, %{})
    |> Contracts.get(key, default)
  end

  defp normalize_extensions(extensions) when is_list(extensions), do: extensions
  defp normalize_extensions(%{} = extensions), do: Enum.into(extensions, [])
  defp normalize_extensions(_extensions), do: []

  defp extract_sensor_payload({:emit, payload}), do: {:ok, payload}
  defp extract_sensor_payload({:signal, payload}), do: {:ok, payload}
  defp extract_sensor_payload(%TriggerRecord{payload: payload}), do: {:ok, payload}
  defp extract_sensor_payload(%{} = payload), do: {:ok, payload}
  defp extract_sensor_payload(_event), do: :ignore
end
