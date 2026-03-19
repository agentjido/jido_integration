defmodule Jido.Integration.V2.TriggerSpec do
  @moduledoc """
  Authored trigger contract for a connector manifest.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @consumer_surface_modes [:common, :connector_local]
  @schema_policy_modes [:defined, :dynamic, :passthrough]

  @consumer_surface_schema Contracts.strict_object!(
                             mode:
                               Contracts.enumish_schema(
                                 @consumer_surface_modes,
                                 "trigger.consumer_surface.mode"
                               ),
                             normalized_id:
                               Contracts.non_empty_string_schema(
                                 "trigger.consumer_surface.normalized_id"
                               )
                               |> Zoi.optional(),
                             sensor_name:
                               Contracts.non_empty_string_schema(
                                 "trigger.consumer_surface.sensor_name"
                               )
                               |> Zoi.optional(),
                             reason:
                               Contracts.non_empty_string_schema(
                                 "trigger.consumer_surface.reason"
                               )
                               |> Zoi.optional()
                           )

  @schema_policy_schema Contracts.strict_object!(
                          config:
                            Contracts.enumish_schema(
                              @schema_policy_modes,
                              "trigger.schema_policy.config"
                            ),
                          signal:
                            Contracts.enumish_schema(
                              @schema_policy_modes,
                              "trigger.schema_policy.signal"
                            ),
                          justification:
                            Contracts.non_empty_string_schema(
                              "trigger.schema_policy.justification"
                            )
                            |> Zoi.optional()
                        )

  @schema Zoi.struct(
            __MODULE__,
            %{
              trigger_id: Contracts.non_empty_string_schema("trigger.trigger_id"),
              name: Contracts.non_empty_string_schema("trigger.name"),
              display_name:
                Contracts.non_empty_string_schema("trigger.display_name") |> Zoi.optional(),
              description: Zoi.string() |> Zoi.nullish() |> Zoi.optional(),
              runtime_class:
                Contracts.enumish_schema([:direct, :session, :stream], "runtime_class"),
              delivery_mode: Contracts.enumish_schema([:webhook, :poll], "trigger.delivery_mode"),
              handler: Contracts.module_schema("trigger.handler"),
              config_schema: Contracts.zoi_schema_schema("config_schema"),
              signal_schema: Contracts.zoi_schema_schema("signal_schema"),
              permissions: Contracts.any_map_schema(),
              checkpoint: Contracts.any_map_schema(),
              dedupe: Contracts.any_map_schema(),
              verification: Contracts.any_map_schema(),
              policy: Contracts.any_map_schema() |> Zoi.default(%{}),
              consumer_surface: @consumer_surface_schema,
              schema_policy: @schema_policy_schema,
              jido: Contracts.any_map_schema(),
              secret_requirements:
                Contracts.string_list_schema("trigger.secret_requirements") |> Zoi.default([]),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type consumer_surface_mode :: :common | :connector_local
  @type schema_policy_mode :: :defined | :dynamic | :passthrough
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = trigger_spec), do: validate(trigger_spec)

  def new(attrs) do
    case Schema.new(__MODULE__, @schema, attrs) do
      {:ok, trigger_spec} -> validate(trigger_spec)
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = trigger_spec) do
    case validate(trigger_spec) do
      {:ok, validated} -> validated
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, trigger_spec} -> trigger_spec
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec common_consumer_surface?(t()) :: boolean()
  def common_consumer_surface?(%__MODULE__{consumer_surface: %{mode: :common}}), do: true
  def common_consumer_surface?(%__MODULE__{}), do: false

  @spec connector_local_consumer_surface?(t()) :: boolean()
  def connector_local_consumer_surface?(%__MODULE__{consumer_surface: %{mode: :connector_local}}),
    do: true

  def connector_local_consumer_surface?(%__MODULE__{}), do: false

  defp validate(%__MODULE__{} = trigger_spec) do
    trigger_spec = %__MODULE__{
      trigger_spec
      | display_name: trigger_spec.display_name || trigger_spec.name
    }

    with :ok <- validate_consumer_surface(trigger_spec),
         :ok <- validate_schema_policy(trigger_spec) do
      {:ok, trigger_spec}
    end
  end

  defp validate_consumer_surface(%__MODULE__{
         consumer_surface: %{mode: :common} = consumer_surface
       }) do
    cond do
      not present_string?(Contracts.get(consumer_surface, :normalized_id)) ->
        error("trigger.consumer_surface.normalized_id is required for common projected surfaces")

      not present_string?(Contracts.get(consumer_surface, :sensor_name)) ->
        error("trigger.consumer_surface.sensor_name is required for common projected surfaces")

      present_string?(Contracts.get(consumer_surface, :reason)) ->
        error("trigger.consumer_surface.reason is not used for common projected surfaces")

      true ->
        :ok
    end
  end

  defp validate_consumer_surface(%__MODULE__{
         consumer_surface: %{mode: :connector_local} = consumer_surface
       }) do
    cond do
      not present_string?(Contracts.get(consumer_surface, :reason)) ->
        error("trigger.consumer_surface.reason is required when a trigger stays connector-local")

      present_string?(Contracts.get(consumer_surface, :normalized_id)) ->
        error("connector-local triggers must not declare trigger.consumer_surface.normalized_id")

      present_string?(Contracts.get(consumer_surface, :sensor_name)) ->
        error("connector-local triggers must not declare trigger.consumer_surface.sensor_name")

      true ->
        :ok
    end
  end

  defp validate_schema_policy(
         %__MODULE__{
           schema_policy: %{config: config_mode, signal: signal_mode} = schema_policy,
           config_schema: config_schema,
           signal_schema: signal_schema
         } = trigger_spec
       ) do
    justification = Contracts.get(schema_policy, :justification)

    cond do
      passthrough_mode?(config_mode) or passthrough_mode?(signal_mode) ->
        if present_string?(justification) do
          validate_passthrough_surface(trigger_spec)
        else
          error(
            "trigger.schema_policy.justification is required when passthrough schemas are declared"
          )
        end

      Contracts.placeholder_zoi_schema?(config_schema) ->
        error(
          "trigger config_schema must not use a placeholder schema without an explicit passthrough exemption"
        )

      Contracts.placeholder_zoi_schema?(signal_schema) ->
        error(
          "trigger signal_schema must not use a placeholder schema without an explicit passthrough exemption"
        )

      present_string?(justification) ->
        error(
          "trigger.schema_policy.justification is only valid when passthrough schemas are declared"
        )

      true ->
        :ok
    end
  end

  defp validate_passthrough_surface(%__MODULE__{} = trigger_spec) do
    if common_consumer_surface?(trigger_spec) do
      error("common projected triggers cannot declare passthrough schemas")
    else
      :ok
    end
  end

  defp passthrough_mode?(:passthrough), do: true
  defp passthrough_mode?(_mode), do: false

  defp present_string?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0

  defp error(message), do: {:error, ArgumentError.exception(message)}
end
