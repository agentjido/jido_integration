defmodule Jido.Integration.V2.ConsumerManifest do
  @moduledoc """
  Declares what an inference consumer can accept from a runtime route.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @contract_version Contracts.inference_contract_version()

  @schema Zoi.struct(
            __MODULE__,
            %{
              contract_version:
                Contracts.non_empty_string_schema("consumer_manifest.contract_version")
                |> Zoi.default(@contract_version),
              consumer: Contracts.atomish_schema("consumer_manifest.consumer"),
              accepted_runtime_kinds:
                Zoi.list(
                  Contracts.enumish_schema(
                    [:client, :task, :service],
                    "consumer_manifest.accepted_runtime_kinds"
                  )
                ),
              accepted_management_modes:
                Zoi.list(
                  Contracts.enumish_schema(
                    [:provider_managed, :jido_managed, :externally_managed],
                    "consumer_manifest.accepted_management_modes"
                  )
                ),
              accepted_protocols:
                Zoi.list(Contracts.atomish_schema("consumer_manifest.accepted_protocols")),
              required_capabilities: Contracts.any_map_schema() |> Zoi.default(%{}),
              optional_capabilities: Contracts.any_map_schema() |> Zoi.default(%{}),
              constraints: Contracts.any_map_schema() |> Zoi.default(%{}),
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
  def new(%__MODULE__{} = manifest), do: normalize(manifest)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = manifest) do
    case normalize(manifest) do
      {:ok, manifest} -> manifest
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, manifest} -> manifest
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = manifest) do
    %{
      contract_version: manifest.contract_version,
      consumer: manifest.consumer,
      accepted_runtime_kinds: manifest.accepted_runtime_kinds,
      accepted_management_modes: manifest.accepted_management_modes,
      accepted_protocols: manifest.accepted_protocols,
      required_capabilities: manifest.required_capabilities,
      optional_capabilities: manifest.optional_capabilities,
      constraints: manifest.constraints,
      metadata: manifest.metadata
    }
  end

  defp normalize(%__MODULE__{} = manifest) do
    {:ok,
     %__MODULE__{
       manifest
       | contract_version:
           Contracts.validate_inference_contract_version!(manifest.contract_version),
         consumer: Contracts.normalize_atomish!(manifest.consumer, "consumer"),
         accepted_runtime_kinds:
           Enum.map(manifest.accepted_runtime_kinds, &Contracts.validate_runtime_kind!/1),
         accepted_management_modes:
           Enum.map(manifest.accepted_management_modes, &Contracts.validate_management_mode!/1),
         accepted_protocols:
           Enum.map(
             manifest.accepted_protocols,
             &Contracts.normalize_atomish!(&1, "accepted_protocols")
           ),
         required_capabilities:
           normalize_map!(manifest.required_capabilities, "required_capabilities"),
         optional_capabilities:
           normalize_map!(manifest.optional_capabilities, "optional_capabilities"),
         constraints: normalize_map!(manifest.constraints, "constraints"),
         metadata: normalize_map!(manifest.metadata, "metadata")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp normalize_map!(%{} = value, _field_name), do: Map.new(value)

  defp normalize_map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end
end
