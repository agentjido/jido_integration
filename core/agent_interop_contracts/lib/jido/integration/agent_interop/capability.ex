defmodule Jido.Integration.AgentInterop.Capability do
  @moduledoc """
  Generic runtime capability advertised by an external agent descriptor.
  """

  alias Jido.Integration.AgentInterop.Validator

  @contract_name "JidoIntegration.AgentRuntimeCapability.v1"
  @classes [
    :model_inference,
    :tool_call,
    :skill_invocation,
    :local_process,
    :http_operation,
    :jsonrpc_operation,
    :stream_attach,
    :external_agent_turn,
    :artifact_read,
    :artifact_write
  ]
  @side_effect_classes [:none, :read, :write, :network, :mutation]
  @artifact_postures [:none, :claim_checked, :redacted]
  @fields [
    :contract_name,
    :capability_ref,
    :class,
    :operation,
    :input_schema_ref,
    :output_schema_ref,
    :side_effect_class,
    :requires_approval?,
    :artifact_posture,
    :credential_classes,
    :metadata
  ]
  @required [:capability_ref, :class, :operation, :input_schema_ref, :output_schema_ref]

  @enforce_keys @required
  defstruct @fields

  @type capability_class ::
          :model_inference
          | :tool_call
          | :skill_invocation
          | :local_process
          | :http_operation
          | :jsonrpc_operation
          | :stream_attach
          | :external_agent_turn
          | :artifact_read
          | :artifact_write
  @type side_effect_class :: :none | :read | :write | :network | :mutation
  @type artifact_posture :: :none | :claim_checked | :redacted
  @type t :: %__MODULE__{}

  @spec classes() :: [capability_class()]
  def classes, do: @classes

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = capability), do: normalize(capability)

  def new(attrs) do
    attrs
    |> build()
    |> normalize()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} -> value
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = capability) do
    capability
    |> Map.from_struct()
    |> Validator.compact_dump()
  end

  defp build(attrs) do
    attrs = Validator.attrs!(attrs, @fields, __MODULE__)
    struct!(__MODULE__, Map.take(attrs, @fields))
  end

  defp normalize(%__MODULE__{} = capability) do
    normalized = %__MODULE__{
      capability
      | contract_name: @contract_name,
        capability_ref: Validator.required_string!(capability.capability_ref, :capability_ref),
        class: Validator.enum!(capability.class, @classes, :class),
        operation: Validator.required_string!(capability.operation, :operation),
        input_schema_ref:
          Validator.required_string!(capability.input_schema_ref, :input_schema_ref),
        output_schema_ref:
          Validator.required_string!(capability.output_schema_ref, :output_schema_ref),
        side_effect_class:
          Validator.enum!(
            capability.side_effect_class || :none,
            @side_effect_classes,
            :side_effect_class
          ),
        requires_approval?:
          Validator.boolean!(capability.requires_approval? || false, :requires_approval?),
        artifact_posture:
          Validator.enum!(
            capability.artifact_posture || :none,
            @artifact_postures,
            :artifact_posture
          ),
        credential_classes:
          Validator.string_list!(capability.credential_classes || [], :credential_classes),
        metadata: Validator.map!(capability.metadata || %{}, :metadata)
    }

    Validator.reject_raw_secret_material!(normalized.metadata, :metadata)
    {:ok, normalized}
  rescue
    error in ArgumentError -> {:error, error}
  end
end
