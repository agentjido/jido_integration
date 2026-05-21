defmodule Jido.Integration.AgentInterop.Descriptor do
  @moduledoc """
  Provider-neutral descriptor for a lower external-agent endpoint.
  """

  alias Jido.Integration.AgentInterop.Validator

  @contract_name "JidoIntegration.AgentInteropDescriptor.v1"
  @protocol_families [:http, :jsonrpc, :grpc, :websocket, :sse, :process, :unknown]
  @fields [
    :contract_name,
    :interop_ref,
    :name,
    :version,
    :protocol_family,
    :endpoint_ref,
    :capability_refs,
    :auth_binding_ref,
    :policy_ref,
    :input_schema_ref,
    :output_schema_ref,
    :streaming?,
    :resumable?,
    :external_spec_refs,
    :metadata
  ]
  @required [
    :interop_ref,
    :name,
    :version,
    :protocol_family,
    :endpoint_ref,
    :capability_refs,
    :auth_binding_ref,
    :policy_ref
  ]

  @enforce_keys @required
  defstruct @fields

  @type protocol_family :: :http | :jsonrpc | :grpc | :websocket | :sse | :process | :unknown
  @type t :: %__MODULE__{}

  @spec protocol_families() :: [protocol_family()]
  def protocol_families, do: @protocol_families

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = descriptor), do: normalize(descriptor)

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
  def to_map(%__MODULE__{} = descriptor) do
    descriptor
    |> Map.from_struct()
    |> Validator.compact_dump()
  end

  defp build(attrs) do
    attrs = Validator.attrs!(attrs, @fields, __MODULE__)
    struct!(__MODULE__, Map.take(attrs, @fields))
  end

  defp normalize(%__MODULE__{} = descriptor) do
    normalized = %__MODULE__{
      descriptor
      | contract_name: @contract_name,
        interop_ref: Validator.required_string!(descriptor.interop_ref, :interop_ref),
        name: Validator.required_string!(descriptor.name, :name),
        version: Validator.required_string!(descriptor.version, :version),
        protocol_family:
          Validator.enum!(descriptor.protocol_family, @protocol_families, :protocol_family),
        endpoint_ref: Validator.required_string!(descriptor.endpoint_ref, :endpoint_ref),
        capability_refs:
          Validator.non_empty_string_list!(descriptor.capability_refs, :capability_refs),
        auth_binding_ref:
          Validator.required_string!(descriptor.auth_binding_ref, :auth_binding_ref),
        policy_ref: Validator.required_string!(descriptor.policy_ref, :policy_ref),
        input_schema_ref:
          Validator.optional_string!(descriptor.input_schema_ref, :input_schema_ref),
        output_schema_ref:
          Validator.optional_string!(descriptor.output_schema_ref, :output_schema_ref),
        streaming?: Validator.boolean!(descriptor.streaming? || false, :streaming?),
        resumable?: Validator.boolean!(descriptor.resumable? || false, :resumable?),
        external_spec_refs:
          Validator.string_list!(descriptor.external_spec_refs || [], :external_spec_refs),
        metadata: Validator.map!(descriptor.metadata || %{}, :metadata)
    }

    Validator.reject_raw_secret_material!(normalized, :descriptor)
    Validator.reject_raw_endpoint_material!(normalized.metadata, :metadata)
    {:ok, normalized}
  rescue
    error in ArgumentError -> {:error, error}
  end
end
