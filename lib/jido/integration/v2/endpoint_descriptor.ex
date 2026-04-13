defmodule Jido.Integration.V2.EndpointDescriptor do
  @moduledoc """
  Execution-ready resolved inference endpoint for one attempt or lease.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @contract_version Contracts.inference_contract_version()

  @schema Zoi.struct(
            __MODULE__,
            %{
              contract_version:
                Contracts.non_empty_string_schema("endpoint_descriptor.contract_version")
                |> Zoi.default(@contract_version),
              endpoint_id: Contracts.non_empty_string_schema("endpoint_descriptor.endpoint_id"),
              runtime_kind:
                Contracts.enumish_schema(
                  [:client, :task, :service],
                  "endpoint_descriptor.runtime_kind"
                ),
              management_mode:
                Contracts.enumish_schema(
                  [:provider_managed, :jido_managed, :externally_managed],
                  "endpoint_descriptor.management_mode"
                ),
              target_class:
                Contracts.enumish_schema(
                  [:cloud_provider, :cli_endpoint, :self_hosted_endpoint],
                  "endpoint_descriptor.target_class"
                ),
              protocol:
                Contracts.enumish_schema(
                  [:openai_chat_completions],
                  "endpoint_descriptor.protocol"
                ),
              base_url: Contracts.non_empty_string_schema("endpoint_descriptor.base_url"),
              headers: Contracts.any_map_schema() |> Zoi.default(%{}),
              provider_identity:
                Contracts.atomish_schema("endpoint_descriptor.provider_identity"),
              model_identity:
                Contracts.non_empty_string_schema("endpoint_descriptor.model_identity"),
              source_runtime: Contracts.atomish_schema("endpoint_descriptor.source_runtime"),
              source_runtime_ref:
                Contracts.non_empty_string_schema("endpoint_descriptor.source_runtime_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              lease_ref:
                Contracts.non_empty_string_schema("endpoint_descriptor.lease_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              health_ref:
                Contracts.non_empty_string_schema("endpoint_descriptor.health_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              boundary_ref:
                Contracts.non_empty_string_schema("endpoint_descriptor.boundary_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              capabilities: Contracts.any_map_schema() |> Zoi.default(%{}),
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
  def new(%__MODULE__{} = endpoint), do: normalize(endpoint)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = endpoint) do
    case normalize(endpoint) do
      {:ok, endpoint} -> endpoint
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, endpoint} -> endpoint
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = endpoint) do
    %{
      "contract_version" => endpoint.contract_version,
      "endpoint_id" => endpoint.endpoint_id,
      "runtime_kind" => endpoint.runtime_kind,
      "management_mode" => endpoint.management_mode,
      "target_class" => endpoint.target_class,
      "protocol" => endpoint.protocol,
      "base_url" => endpoint.base_url,
      "headers" => endpoint.headers,
      "provider_identity" => endpoint.provider_identity,
      "model_identity" => endpoint.model_identity,
      "source_runtime" => endpoint.source_runtime,
      "source_runtime_ref" => endpoint.source_runtime_ref,
      "lease_ref" => endpoint.lease_ref,
      "health_ref" => endpoint.health_ref,
      "boundary_ref" => endpoint.boundary_ref,
      "capabilities" => endpoint.capabilities,
      "metadata" => endpoint.metadata
    }
    |> Contracts.dump_json_safe!()
  end

  defp normalize(%__MODULE__{} = endpoint) do
    {:ok,
     %__MODULE__{
       endpoint
       | contract_version:
           Contracts.validate_inference_contract_version!(endpoint.contract_version),
         runtime_kind: Contracts.validate_runtime_kind!(endpoint.runtime_kind),
         management_mode: Contracts.validate_management_mode!(endpoint.management_mode),
         target_class: Contracts.validate_inference_target_class!(endpoint.target_class),
         protocol: Contracts.validate_inference_protocol!(endpoint.protocol),
         headers: normalize_headers!(endpoint.headers),
         provider_identity:
           Contracts.normalize_atomish!(endpoint.provider_identity, "provider_identity"),
         source_runtime: Contracts.normalize_atomish!(endpoint.source_runtime, "source_runtime"),
         capabilities: normalize_map!(endpoint.capabilities, "capabilities"),
         metadata: normalize_map!(endpoint.metadata, "metadata")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp normalize_headers!(%{} = headers) do
    headers
    |> Enum.into(%{}, fn {key, value} ->
      {
        key |> to_string() |> Contracts.validate_non_empty_string!("headers key"),
        value |> to_string() |> Contracts.validate_non_empty_string!("headers value")
      }
    end)
  end

  defp normalize_headers!(value) do
    raise ArgumentError, "headers must be a map, got: #{inspect(value)}"
  end

  defp normalize_map!(%{} = value, _field_name), do: Map.new(value)

  defp normalize_map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end
end
