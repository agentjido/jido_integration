defmodule Jido.Integration.V2.CompatibilityResult do
  @moduledoc """
  Typed compatibility outcome for an admitted inference route.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @contract_version Contracts.inference_contract_version()

  @schema Zoi.struct(
            __MODULE__,
            %{
              contract_version:
                Contracts.non_empty_string_schema("compatibility_result.contract_version")
                |> Zoi.default(@contract_version),
              compatible?: Zoi.boolean(),
              reason: Contracts.atomish_schema("compatibility_result.reason"),
              resolved_runtime_kind:
                Contracts.enumish_schema(
                  [:client, :task, :service],
                  "compatibility_result.resolved_runtime_kind"
                )
                |> Zoi.nullish()
                |> Zoi.optional(),
              resolved_management_mode:
                Contracts.enumish_schema(
                  [:provider_managed, :jido_managed, :externally_managed],
                  "compatibility_result.resolved_management_mode"
                )
                |> Zoi.nullish()
                |> Zoi.optional(),
              resolved_protocol:
                Contracts.atomish_schema("compatibility_result.resolved_protocol")
                |> Zoi.nullish()
                |> Zoi.optional(),
              warnings:
                Zoi.list(Contracts.atomish_schema("compatibility_result.warnings"))
                |> Zoi.default([]),
              missing_requirements:
                Zoi.list(Contracts.atomish_schema("compatibility_result.missing_requirements"))
                |> Zoi.default([]),
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
  def new(%__MODULE__{} = result), do: normalize(result)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = result) do
    case normalize(result) do
      {:ok, result} -> result
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, result} -> result
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = result) do
    %{
      contract_version: result.contract_version,
      compatible?: result.compatible?,
      reason: result.reason,
      resolved_runtime_kind: result.resolved_runtime_kind,
      resolved_management_mode: result.resolved_management_mode,
      resolved_protocol: result.resolved_protocol,
      warnings: result.warnings,
      missing_requirements: result.missing_requirements,
      metadata: result.metadata
    }
  end

  defp normalize(%__MODULE__{} = result) do
    {:ok,
     %__MODULE__{
       result
       | contract_version:
           Contracts.validate_inference_contract_version!(result.contract_version),
         reason: Contracts.normalize_atomish!(result.reason, "reason"),
         resolved_runtime_kind: normalize_optional_runtime_kind(result.resolved_runtime_kind),
         resolved_management_mode:
           normalize_optional_management_mode(result.resolved_management_mode),
         resolved_protocol: normalize_optional_protocol(result.resolved_protocol),
         warnings: Contracts.normalize_atomish_list!(result.warnings, "warnings"),
         missing_requirements:
           Contracts.normalize_atomish_list!(
             result.missing_requirements,
             "missing_requirements"
           ),
         metadata: normalize_map!(result.metadata, "metadata")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp normalize_optional_runtime_kind(nil), do: nil
  defp normalize_optional_runtime_kind(value), do: Contracts.validate_runtime_kind!(value)

  defp normalize_optional_management_mode(nil), do: nil
  defp normalize_optional_management_mode(value), do: Contracts.validate_management_mode!(value)

  defp normalize_optional_protocol(nil), do: nil

  defp normalize_optional_protocol(value),
    do: Contracts.normalize_atomish!(value, "resolved_protocol")

  defp normalize_map!(%{} = value, _field_name), do: Map.new(value)

  defp normalize_map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end
end
