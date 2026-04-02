defmodule Jido.Integration.V2.InferenceResult do
  @moduledoc """
  Canonical terminal inference outcome projected by the control plane.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @contract_version Contracts.inference_contract_version()

  @schema Zoi.struct(
            __MODULE__,
            %{
              contract_version:
                Contracts.non_empty_string_schema("inference_result.contract_version")
                |> Zoi.default(@contract_version),
              run_id: Contracts.non_empty_string_schema("inference_result.run_id"),
              attempt_id: Contracts.non_empty_string_schema("inference_result.attempt_id"),
              status:
                Contracts.enumish_schema([:ok, :error, :cancelled], "inference_result.status"),
              streaming?: Zoi.boolean() |> Zoi.default(false),
              endpoint_id:
                Contracts.non_empty_string_schema("inference_result.endpoint_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              stream_id:
                Contracts.non_empty_string_schema("inference_result.stream_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              finish_reason:
                Contracts.atomish_schema("inference_result.finish_reason")
                |> Zoi.nullish()
                |> Zoi.optional(),
              usage: Contracts.any_map_schema() |> Zoi.nullish() |> Zoi.optional(),
              error: Contracts.any_map_schema() |> Zoi.nullish() |> Zoi.optional(),
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
      run_id: result.run_id,
      attempt_id: result.attempt_id,
      status: result.status,
      streaming?: result.streaming?,
      endpoint_id: result.endpoint_id,
      stream_id: result.stream_id,
      finish_reason: result.finish_reason,
      usage: result.usage,
      error: result.error,
      metadata: result.metadata
    }
  end

  defp normalize(%__MODULE__{} = result) do
    attempt = Contracts.attempt_from_id!(result.run_id, result.attempt_id)
    expected_attempt_id = Contracts.attempt_id(result.run_id, attempt)

    if result.attempt_id != expected_attempt_id do
      raise ArgumentError,
            "attempt_id must match run_id and attempt: #{inspect({result.run_id, result.attempt_id})}"
    end

    {:ok,
     %__MODULE__{
       result
       | contract_version:
           Contracts.validate_inference_contract_version!(result.contract_version),
         status: Contracts.validate_inference_status!(result.status),
         finish_reason: normalize_optional_atomish(result.finish_reason, "finish_reason"),
         usage: normalize_optional_map(result.usage, "usage"),
         error: normalize_optional_map(result.error, "error"),
         metadata: normalize_map!(result.metadata, "metadata")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp normalize_optional_atomish(nil, _field_name), do: nil

  defp normalize_optional_atomish(value, field_name) do
    Contracts.normalize_atomish!(value, field_name)
  end

  defp normalize_optional_map(nil, _field_name), do: nil
  defp normalize_optional_map(%{} = value, _field_name), do: Map.new(value)

  defp normalize_optional_map(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end

  defp normalize_map!(%{} = value, _field_name), do: Map.new(value)

  defp normalize_map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end
end
