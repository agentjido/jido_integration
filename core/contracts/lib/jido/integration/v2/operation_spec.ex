defmodule Jido.Integration.V2.OperationSpec do
  @moduledoc """
  Authored operation contract for a connector manifest.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @consumer_surface_modes [:common, :connector_local]
  @schema_policy_modes [:defined, :dynamic, :passthrough]

  @consumer_surface_schema Contracts.strict_object!(
                             mode:
                               Contracts.enumish_schema(
                                 @consumer_surface_modes,
                                 "operation.consumer_surface.mode"
                               ),
                             normalized_id:
                               Contracts.non_empty_string_schema(
                                 "operation.consumer_surface.normalized_id"
                               )
                               |> Zoi.optional(),
                             action_name:
                               Contracts.non_empty_string_schema(
                                 "operation.consumer_surface.action_name"
                               )
                               |> Zoi.optional(),
                             reason:
                               Contracts.non_empty_string_schema(
                                 "operation.consumer_surface.reason"
                               )
                               |> Zoi.optional()
                           )

  @schema_policy_schema Contracts.strict_object!(
                          input:
                            Contracts.enumish_schema(
                              @schema_policy_modes,
                              "operation.schema_policy.input"
                            ),
                          output:
                            Contracts.enumish_schema(
                              @schema_policy_modes,
                              "operation.schema_policy.output"
                            ),
                          justification:
                            Contracts.non_empty_string_schema(
                              "operation.schema_policy.justification"
                            )
                            |> Zoi.optional()
                        )

  @schema Zoi.struct(
            __MODULE__,
            %{
              operation_id: Contracts.non_empty_string_schema("operation.operation_id"),
              name: Contracts.non_empty_string_schema("operation.name"),
              display_name:
                Contracts.non_empty_string_schema("operation.display_name") |> Zoi.optional(),
              description: Zoi.string() |> Zoi.nullish() |> Zoi.optional(),
              runtime_class:
                Contracts.enumish_schema([:direct, :session, :stream], "runtime_class"),
              transport_mode: Contracts.atomish_schema("operation.transport_mode"),
              handler: Contracts.module_schema("operation.handler"),
              input_schema: Contracts.zoi_schema_schema("input_schema"),
              output_schema: Contracts.zoi_schema_schema("output_schema"),
              permissions: Contracts.any_map_schema(),
              runtime: Contracts.any_map_schema() |> Zoi.default(%{}),
              policy: Contracts.any_map_schema(),
              upstream: Contracts.any_map_schema(),
              consumer_surface: @consumer_surface_schema,
              schema_policy: @schema_policy_schema,
              jido: Contracts.any_map_schema(),
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
  def new(%__MODULE__{} = operation_spec), do: validate(operation_spec)

  def new(attrs) do
    case Schema.new(__MODULE__, @schema, attrs) do
      {:ok, operation_spec} -> validate(operation_spec)
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = operation_spec) do
    case validate(operation_spec) do
      {:ok, validated} -> validated
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, operation_spec} -> operation_spec
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

  @spec normalized_surface_id(t()) :: String.t() | nil
  def normalized_surface_id(%__MODULE__{consumer_surface: consumer_surface}) do
    Contracts.get(consumer_surface, :normalized_id)
  end

  @spec action_name(t()) :: String.t() | nil
  def action_name(%__MODULE__{consumer_surface: consumer_surface}) do
    Contracts.get(consumer_surface, :action_name)
  end

  defp validate(%__MODULE__{} = operation_spec) do
    operation_spec = %__MODULE__{
      operation_spec
      | display_name: operation_spec.display_name || operation_spec.name
    }

    with :ok <- validate_consumer_surface(operation_spec),
         :ok <- validate_schema_policy(operation_spec) do
      {:ok, operation_spec}
    end
  end

  defp validate_consumer_surface(%__MODULE__{
         consumer_surface: %{mode: :common} = consumer_surface
       }) do
    normalized_id = Contracts.get(consumer_surface, :normalized_id)
    action_name = Contracts.get(consumer_surface, :action_name)

    cond do
      not present_string?(normalized_id) ->
        error(
          "operation.consumer_surface.normalized_id is required for common projected surfaces"
        )

      not present_string?(action_name) ->
        error("operation.consumer_surface.action_name is required for common projected surfaces")

      present_string?(Contracts.get(consumer_surface, :reason)) ->
        error("operation.consumer_surface.reason is not used for common projected surfaces")

      true ->
        :ok
    end
  end

  defp validate_consumer_surface(%__MODULE__{
         consumer_surface: %{mode: :connector_local} = consumer_surface
       }) do
    cond do
      not present_string?(Contracts.get(consumer_surface, :reason)) ->
        error(
          "operation.consumer_surface.reason is required when an operation stays connector-local"
        )

      present_string?(Contracts.get(consumer_surface, :normalized_id)) ->
        error(
          "connector-local operations must not declare operation.consumer_surface.normalized_id"
        )

      present_string?(Contracts.get(consumer_surface, :action_name)) ->
        error(
          "connector-local operations must not declare operation.consumer_surface.action_name"
        )

      true ->
        :ok
    end
  end

  defp validate_schema_policy(
         %__MODULE__{
           schema_policy: %{input: input_mode, output: output_mode} = schema_policy,
           input_schema: input_schema,
           output_schema: output_schema
         } = operation_spec
       ) do
    justification = Contracts.get(schema_policy, :justification)

    cond do
      passthrough_mode?(input_mode) or passthrough_mode?(output_mode) ->
        if present_string?(justification) do
          validate_passthrough_surface(operation_spec)
        else
          error(
            "operation.schema_policy.justification is required when passthrough schemas are declared"
          )
        end

      Contracts.placeholder_zoi_schema?(input_schema) ->
        error(
          "operation input_schema must not use a placeholder schema without an explicit passthrough exemption"
        )

      Contracts.placeholder_zoi_schema?(output_schema) ->
        error(
          "operation output_schema must not use a placeholder schema without an explicit passthrough exemption"
        )

      present_string?(justification) ->
        error(
          "operation.schema_policy.justification is only valid when passthrough schemas are declared"
        )

      true ->
        :ok
    end
  end

  defp validate_passthrough_surface(%__MODULE__{} = operation_spec) do
    if common_consumer_surface?(operation_spec) do
      error("common projected operations cannot declare passthrough schemas")
    else
      :ok
    end
  end

  defp passthrough_mode?(:passthrough), do: true
  defp passthrough_mode?(_mode), do: false

  defp present_string?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0

  defp error(message), do: {:error, ArgumentError.exception(message)}
end
