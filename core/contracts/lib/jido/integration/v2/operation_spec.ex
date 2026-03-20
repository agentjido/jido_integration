defmodule Jido.Integration.V2.OperationSpec do
  @moduledoc """
  Authored operation contract for a connector manifest.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @consumer_surface_modes [:common, :connector_local]
  @schema_policy_modes [:defined, :dynamic, :passthrough]
  @schema_strategies [:static, :late_bound_input, :late_bound_output, :late_bound_input_output]
  @late_bound_schema_strategies [:late_bound_input, :late_bound_output, :late_bound_input_output]
  @non_direct_runtime_keys [:driver, :provider, :options]
  @runtime_family_keys [
    :session_affinity,
    :resumable,
    :approval_required,
    :stream_capable,
    :lifecycle_owner,
    :runtime_ref
  ]
  @runtime_family_session_affinities [:none, :connection, :target]
  @runtime_family_lifecycle_owners [:asm, :jido_session]
  @runtime_family_runtime_refs [:session, :run]

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
  @type schema_strategy ::
          :static | :late_bound_input | :late_bound_output | :late_bound_input_output
  @type schema_surface :: :input | :output
  @type runtime_family_session_affinity :: :none | :connection | :target
  @type runtime_family_lifecycle_owner :: :asm | :jido_session
  @type runtime_family_ref :: :session | :run
  @type runtime_family :: %{
          session_affinity: runtime_family_session_affinity(),
          resumable: boolean(),
          approval_required: boolean(),
          stream_capable: boolean(),
          lifecycle_owner: runtime_family_lifecycle_owner(),
          runtime_ref: runtime_family_ref()
        }
  @type schema_slot :: %{
          surface: schema_surface(),
          path: [String.t()],
          kind: atom(),
          source: atom()
        }
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

  @spec runtime_driver(t()) :: String.t() | nil
  def runtime_driver(%__MODULE__{runtime: runtime}) do
    case Contracts.get(runtime, :driver) do
      nil -> nil
      value -> normalize_runtime_driver(value)
    end
  end

  @spec runtime_provider(t()) :: atom() | nil
  def runtime_provider(%__MODULE__{runtime: runtime}) do
    case Contracts.get(runtime, :provider) do
      nil -> nil
      value -> normalize_runtime_provider(value)
    end
  end

  @spec runtime_options(t()) :: map()
  def runtime_options(%__MODULE__{runtime: runtime}) do
    case Contracts.get(runtime, :options, %{}) do
      %{} = options -> options
      _other -> %{}
    end
  end

  @spec runtime_family(t()) :: runtime_family() | nil
  def runtime_family(%__MODULE__{metadata: metadata}) do
    case Contracts.get(metadata, :runtime_family) do
      %{} = runtime_family -> normalize_runtime_family(runtime_family)
      _other -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @spec schema_strategy(t()) :: schema_strategy() | nil
  def schema_strategy(%__MODULE__{metadata: metadata}) do
    Contracts.get(metadata, :schema_strategy)
  end

  @spec schema_context_source(t()) :: atom() | nil
  def schema_context_source(%__MODULE__{metadata: metadata}) do
    Contracts.get(metadata, :schema_context_source)
  end

  @spec schema_slots(t()) :: [schema_slot()]
  def schema_slots(%__MODULE__{metadata: metadata}) do
    case Contracts.get(metadata, :schema_slots, []) do
      slots when is_list(slots) -> slots
      _other -> []
    end
  end

  @spec late_bound_schema?(t()) :: boolean()
  def late_bound_schema?(%__MODULE__{} = operation_spec) do
    schema_strategy(operation_spec) in @late_bound_schema_strategies
  end

  defp validate(%__MODULE__{} = operation_spec) do
    operation_spec = %__MODULE__{
      operation_spec
      | display_name: operation_spec.display_name || operation_spec.name
    }

    with :ok <- validate_consumer_surface(operation_spec),
         :ok <- validate_schema_policy(operation_spec),
         :ok <- validate_schema_metadata(operation_spec),
         :ok <- validate_runtime_contract(operation_spec) do
      {:ok, operation_spec}
    end
  end

  defp validate_runtime_contract(%__MODULE__{runtime_class: runtime_class} = operation_spec)
       when runtime_class in [:session, :stream] do
    with :ok <- validate_non_direct_runtime(operation_spec),
         :ok <- validate_runtime_family_requirement(operation_spec) do
      validate_runtime_family_shape(operation_spec)
    end
  end

  defp validate_runtime_contract(%__MODULE__{} = operation_spec) do
    validate_runtime_family_shape(operation_spec)
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

  defp validate_schema_metadata(%__MODULE__{} = operation_spec) do
    strategy = schema_strategy(operation_spec)
    context_source = schema_context_source(operation_spec)
    raw_slots = Contracts.get(operation_spec.metadata, :schema_slots)
    slots_declared? = schema_slots_declared?(operation_spec.metadata)

    with :ok <-
           validate_schema_metadata_shape(strategy, context_source, slots_declared?, raw_slots) do
      validate_schema_metadata_strategy(strategy, context_source, schema_slots(operation_spec))
    end
  end

  defp validate_schema_metadata_shape(nil, nil, false, _raw_slots), do: :ok

  defp validate_schema_metadata_shape(nil, _context_source, _slots_declared?, _raw_slots) do
    error("operation.metadata.schema_strategy is required when schema metadata is declared")
  end

  defp validate_schema_metadata_shape(_strategy, _context_source, true, raw_slots)
       when not is_list(raw_slots) do
    error("operation.metadata.schema_slots must be a list when schema metadata is declared")
  end

  defp validate_schema_metadata_shape(strategy, _context_source, _slots_declared?, _raw_slots)
       when strategy not in @schema_strategies do
    error("operation.metadata.schema_strategy must be one of #{inspect(@schema_strategies)}")
  end

  defp validate_schema_metadata_shape(_strategy, _context_source, _slots_declared?, _raw_slots),
    do: :ok

  defp validate_non_direct_runtime(%__MODULE__{runtime: runtime}) when is_map(runtime) do
    unknown_keys =
      runtime
      |> Map.keys()
      |> Enum.reject(&(normalize_runtime_key(&1) in @non_direct_runtime_keys))
      |> Enum.sort()

    cond do
      unknown_keys != [] ->
        error(
          "operation.runtime only supports driver, provider, and options for session and stream authored routing"
        )

      is_nil(runtime_driver_value(runtime)) ->
        error("operation.runtime.driver is required for session and stream authored routing")

      true ->
        with :ok <- validate_runtime_driver(runtime_driver_value(runtime)),
             :ok <- validate_runtime_provider_value(runtime_provider_value(runtime)) do
          validate_runtime_options(runtime_options_value(runtime))
        end
    end
  end

  defp validate_non_direct_runtime(%__MODULE__{}), do: error("operation.runtime must be a map")

  defp validate_runtime_family_requirement(%__MODULE__{} = operation_spec) do
    if common_consumer_surface?(operation_spec) and is_nil(runtime_family(operation_spec)) do
      error(
        "operation.metadata.runtime_family is required for common projected session and stream surfaces"
      )
    else
      :ok
    end
  end

  defp validate_runtime_family_shape(%__MODULE__{} = operation_spec) do
    case Contracts.get(operation_spec.metadata, :runtime_family) do
      nil ->
        :ok

      %{} = runtime_family ->
        normalize_runtime_family(runtime_family)
        :ok

      _other ->
        error("operation.metadata.runtime_family must be a map when declared")
    end
  end

  defp validate_schema_metadata_strategy(nil, _context_source, _slots), do: :ok

  defp validate_schema_metadata_strategy(:static, context_source, slots) do
    validate_static_schema_metadata(context_source, slots)
  end

  defp validate_schema_metadata_strategy(strategy, context_source, slots)
       when strategy in @late_bound_schema_strategies do
    validate_late_bound_schema_metadata(strategy, context_source, slots)
  end

  defp validate_static_schema_metadata(context_source, slots) do
    cond do
      context_source not in [nil, :none] ->
        error("operation.metadata.schema_context_source must be :none for static operations")

      slots != [] ->
        error("operation.metadata.schema_slots must be empty for static operations")

      true ->
        :ok
    end
  end

  defp validate_late_bound_schema_metadata(strategy, context_source, slots) do
    cond do
      not real_schema_source?(context_source) ->
        error(
          "operation.metadata.schema_context_source must identify a real lookup source when late-bound schema metadata is declared"
        )

      not is_list(slots) or slots == [] ->
        error(
          "operation.metadata.schema_slots must be a non-empty list when late-bound schema metadata is declared"
        )

      true ->
        case validate_schema_slots(slots) do
          :ok -> validate_schema_slot_surfaces(strategy, slots)
          {:error, _error} = error -> error
        end
    end
  end

  defp validate_schema_slot_surfaces(strategy, slots) do
    surfaces = normalize_schema_slot_surfaces(slots)

    case strategy do
      :late_bound_input ->
        validate_exact_schema_slot_surfaces(
          surfaces,
          [:input],
          "operation.metadata.schema_slots surfaces must all be :input for :late_bound_input"
        )

      :late_bound_output ->
        validate_exact_schema_slot_surfaces(
          surfaces,
          [:output],
          "operation.metadata.schema_slots surfaces must all be :output for :late_bound_output"
        )

      :late_bound_input_output ->
        validate_input_output_schema_slot_surfaces(surfaces)
    end
  end

  defp validate_exact_schema_slot_surfaces(surfaces, expected_surfaces, _message)
       when surfaces == expected_surfaces,
       do: :ok

  defp validate_exact_schema_slot_surfaces(_surfaces, _expected_surfaces, message),
    do: error(message)

  defp validate_input_output_schema_slot_surfaces(surfaces) do
    if Enum.all?([:input, :output], &(&1 in surfaces)) do
      :ok
    else
      error(
        "operation.metadata.schema_slots must include both :input and :output for :late_bound_input_output"
      )
    end
  end

  defp validate_schema_slots(slots) do
    Enum.reduce_while(Enum.with_index(slots), :ok, fn {slot, index}, :ok ->
      case validate_schema_slot(slot, index) do
        :ok -> {:cont, :ok}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp validate_schema_slot(slot, index) when is_map(slot) do
    cond do
      Contracts.get(slot, :surface) not in [:input, :output] ->
        error("operation.metadata.schema_slots[#{index}].surface must be :input or :output")

      not valid_path?(Contracts.get(slot, :path)) ->
        error(
          "operation.metadata.schema_slots[#{index}].path must be a non-empty list of strings"
        )

      not present_atom?(Contracts.get(slot, :kind)) ->
        error("operation.metadata.schema_slots[#{index}].kind must be an atom")

      not real_schema_source?(Contracts.get(slot, :source)) ->
        error(
          "operation.metadata.schema_slots[#{index}].source must identify a real lookup source"
        )

      true ->
        :ok
    end
  end

  defp validate_schema_slot(_slot, index) do
    error("operation.metadata.schema_slots[#{index}] must be a map")
  end

  defp normalize_schema_slot_surfaces(slots) do
    slots
    |> Enum.map(&Contracts.get(&1, :surface))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp schema_slots_declared?(metadata) do
    Map.has_key?(metadata, :schema_slots) or Map.has_key?(metadata, "schema_slots")
  end

  defp passthrough_mode?(:passthrough), do: true
  defp passthrough_mode?(_mode), do: false

  defp valid_path?(value) when is_list(value) do
    value != [] and Enum.all?(value, &present_string?/1)
  end

  defp valid_path?(_value), do: false

  defp real_schema_source?(value), do: present_atom?(value) and value != :none
  defp runtime_driver_value(runtime), do: Contracts.get(runtime, :driver)
  defp runtime_provider_value(runtime), do: Contracts.get(runtime, :provider)
  defp runtime_options_value(runtime), do: Contracts.get(runtime, :options, %{})

  defp validate_runtime_driver(value) do
    value
    |> normalize_runtime_driver()
    |> then(fn _driver -> :ok end)
  rescue
    ArgumentError -> error("operation.runtime.driver must be a non-empty string or atom")
  end

  defp validate_runtime_provider_value(nil), do: :ok

  defp validate_runtime_provider_value(value) do
    value
    |> normalize_runtime_provider()
    |> then(fn _provider -> :ok end)
  rescue
    ArgumentError ->
      error("operation.runtime.provider must be a non-empty string or atom when declared")
  end

  defp validate_runtime_options(%{}), do: :ok

  defp validate_runtime_options(_other),
    do: error("operation.runtime.options must be a map when declared")

  defp normalize_runtime_driver(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_runtime_driver(value),
    do: Contracts.validate_non_empty_string!(value, "operation.runtime.driver")

  defp normalize_runtime_provider(value) when is_atom(value), do: value

  defp normalize_runtime_provider(value) when is_binary(value) do
    value
    |> Contracts.validate_non_empty_string!("operation.runtime.provider")
    |> String.to_atom()
  end

  defp normalize_runtime_provider(value) do
    raise ArgumentError,
          "operation.runtime.provider must be a non-empty string or atom, got: #{inspect(value)}"
  end

  defp normalize_runtime_key(key) when key in @non_direct_runtime_keys, do: key

  defp normalize_runtime_key(key) when is_binary(key) do
    case key do
      "driver" -> :driver
      "provider" -> :provider
      "options" -> :options
      _other -> nil
    end
  end

  defp normalize_runtime_key(_key), do: nil

  defp normalize_runtime_family(runtime_family) when is_map(runtime_family) do
    keys =
      runtime_family
      |> Map.keys()
      |> Enum.map(&normalize_runtime_family_key/1)
      |> Enum.sort()

    if keys != Enum.sort(@runtime_family_keys) do
      raise ArgumentError,
            "operation.metadata.runtime_family must include exactly #{inspect(@runtime_family_keys)}"
    end

    %{
      session_affinity:
        normalize_runtime_family_enum(
          Contracts.get(runtime_family, :session_affinity),
          @runtime_family_session_affinities,
          "operation.metadata.runtime_family.session_affinity"
        ),
      resumable:
        normalize_runtime_family_boolean(
          Contracts.get(runtime_family, :resumable),
          "operation.metadata.runtime_family.resumable"
        ),
      approval_required:
        normalize_runtime_family_boolean(
          Contracts.get(runtime_family, :approval_required),
          "operation.metadata.runtime_family.approval_required"
        ),
      stream_capable:
        normalize_runtime_family_boolean(
          Contracts.get(runtime_family, :stream_capable),
          "operation.metadata.runtime_family.stream_capable"
        ),
      lifecycle_owner:
        normalize_runtime_family_enum(
          Contracts.get(runtime_family, :lifecycle_owner),
          @runtime_family_lifecycle_owners,
          "operation.metadata.runtime_family.lifecycle_owner"
        ),
      runtime_ref:
        normalize_runtime_family_enum(
          Contracts.get(runtime_family, :runtime_ref),
          @runtime_family_runtime_refs,
          "operation.metadata.runtime_family.runtime_ref"
        )
    }
  end

  defp normalize_runtime_family(_other) do
    raise ArgumentError, "operation.metadata.runtime_family must be a map when declared"
  end

  defp normalize_runtime_family_key(key) when key in @runtime_family_keys, do: key

  defp normalize_runtime_family_key(key) when is_binary(key) do
    case key do
      "session_affinity" -> :session_affinity
      "resumable" -> :resumable
      "approval_required" -> :approval_required
      "stream_capable" -> :stream_capable
      "lifecycle_owner" -> :lifecycle_owner
      "runtime_ref" -> :runtime_ref
      _other -> key
    end
  end

  defp normalize_runtime_family_key(key), do: key

  defp normalize_runtime_family_enum(value, allowed_values, field_name) when is_atom(value) do
    if value in allowed_values do
      value
    else
      raise ArgumentError, "#{field_name} must be one of #{inspect(allowed_values)}"
    end
  end

  defp normalize_runtime_family_enum(value, allowed_values, field_name) when is_binary(value) do
    atom_value = String.to_atom(value)

    if atom_value in allowed_values do
      atom_value
    else
      raise ArgumentError, "#{field_name} must be one of #{inspect(allowed_values)}"
    end
  end

  defp normalize_runtime_family_enum(_value, allowed_values, field_name) do
    raise ArgumentError, "#{field_name} must be one of #{inspect(allowed_values)}"
  end

  defp normalize_runtime_family_boolean(value, _field_name) when is_boolean(value), do: value

  defp normalize_runtime_family_boolean(value, field_name) do
    raise ArgumentError, "#{field_name} must be a boolean, got: #{inspect(value)}"
  end

  defp present_atom?(value), do: is_atom(value)
  defp present_string?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0

  defp error(message), do: {:error, ArgumentError.exception(message)}
end
