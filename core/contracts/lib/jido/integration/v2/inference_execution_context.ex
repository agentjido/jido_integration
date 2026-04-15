defmodule Jido.Integration.V2.InferenceExecutionContext do
  @moduledoc """
  Control-plane context attached to an admitted inference attempt.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @contract_version Contracts.inference_contract_version()

  @schema Zoi.struct(
            __MODULE__,
            %{
              contract_version:
                Contracts.non_empty_string_schema("inference_execution_context.contract_version")
                |> Zoi.default(@contract_version),
              run_id: Contracts.non_empty_string_schema("inference_execution_context.run_id"),
              attempt_id:
                Contracts.non_empty_string_schema("inference_execution_context.attempt_id"),
              authority_source:
                Contracts.enumish_schema(
                  [:jido_integration, :external],
                  "inference_execution_context.authority_source"
                ),
              decision_ref:
                Contracts.non_empty_string_schema("inference_execution_context.decision_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              authority_ref:
                Contracts.non_empty_string_schema("inference_execution_context.authority_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              boundary_ref:
                Contracts.non_empty_string_schema("inference_execution_context.boundary_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              credential_scope: Contracts.any_map_schema() |> Zoi.default(%{}),
              network_policy: Contracts.any_map_schema() |> Zoi.default(%{}),
              observability: Contracts.any_map_schema() |> Zoi.default(%{}),
              streaming_policy: Contracts.any_map_schema() |> Zoi.default(%{}),
              replay: Contracts.any_map_schema() |> Zoi.default(%{}),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = context), do: normalize(context)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = context) do
    case normalize(context) do
      {:ok, context} -> context
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, context} -> context
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = context) do
    %{
      "contract_version" => context.contract_version,
      "run_id" => context.run_id,
      "attempt_id" => context.attempt_id,
      "authority_source" => context.authority_source,
      "decision_ref" => context.decision_ref,
      "authority_ref" => context.authority_ref,
      "boundary_ref" => context.boundary_ref,
      "credential_scope" => context.credential_scope,
      "network_policy" => context.network_policy,
      "observability" => context.observability,
      "streaming_policy" => context.streaming_policy,
      "replay" => context.replay,
      "metadata" => context.metadata
    }
    |> Contracts.dump_json_safe!()
  end

  defp normalize(%__MODULE__{} = context) do
    attempt = Contracts.attempt_from_id!(context.run_id, context.attempt_id)
    expected_attempt_id = Contracts.attempt_id(context.run_id, attempt)

    if context.attempt_id != expected_attempt_id do
      raise ArgumentError,
            "attempt_id must match run_id and attempt: #{inspect({context.run_id, context.attempt_id})}"
    end

    {:ok,
     %__MODULE__{
       context
       | contract_version:
           Contracts.validate_inference_contract_version!(context.contract_version),
         authority_source: Contracts.validate_authority_source!(context.authority_source),
         credential_scope: normalize_map!(context.credential_scope, "credential_scope"),
         network_policy: normalize_map!(context.network_policy, "network_policy"),
         observability: normalize_map!(context.observability, "observability"),
         streaming_policy: normalize_streaming_policy!(context.streaming_policy),
         replay: normalize_replay!(context.replay),
         metadata: normalize_map!(context.metadata, "metadata")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp normalize_streaming_policy!(%{} = streaming_policy) do
    checkpoint_policy =
      streaming_policy
      |> Contracts.get(:checkpoint_policy, :disabled)
      |> Contracts.validate_inference_checkpoint_policy!()

    streaming_policy
    |> Map.new()
    |> Map.drop([:checkpoint_policy, "checkpoint_policy"])
    |> Map.put(:checkpoint_policy, checkpoint_policy)
  end

  defp normalize_streaming_policy!(value) do
    raise ArgumentError, "streaming_policy must be a map, got: #{inspect(value)}"
  end

  defp normalize_replay!(%{} = replay) do
    replayable? =
      normalize_boolean!(Contracts.get(replay, :replayable?, false), "replay.replayable?")

    recovery_class = normalize_optional_atomish(Contracts.get(replay, :recovery_class))

    replay
    |> Map.new()
    |> Map.drop([:replayable?, "replayable?", :recovery_class, "recovery_class"])
    |> Map.put(:replayable?, replayable?)
    |> Map.put(:recovery_class, recovery_class)
  end

  defp normalize_replay!(value) do
    raise ArgumentError, "replay must be a map, got: #{inspect(value)}"
  end

  defp normalize_boolean!(value, _field_name) when is_boolean(value), do: value

  defp normalize_boolean!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a boolean, got: #{inspect(value)}"
  end

  defp normalize_optional_atomish(nil), do: nil

  defp normalize_optional_atomish(value),
    do: Contracts.normalize_atomish!(value, "replay.recovery_class")

  defp normalize_map!(%{} = value, _field_name), do: Map.new(value)

  defp normalize_map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end
end
