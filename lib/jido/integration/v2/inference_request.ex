defmodule Jido.Integration.V2.InferenceRequest do
  @moduledoc """
  Normalized admitted inference intent before target resolution.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @contract_version Contracts.inference_contract_version()

  @schema Zoi.struct(
            __MODULE__,
            %{
              contract_version:
                Contracts.non_empty_string_schema("inference_request.contract_version")
                |> Zoi.default(@contract_version),
              request_id: Contracts.non_empty_string_schema("inference_request.request_id"),
              operation:
                Contracts.enumish_schema(
                  [:generate_text, :stream_text],
                  "inference_request.operation"
                ),
              messages: Zoi.list(Contracts.any_map_schema()),
              prompt:
                Contracts.non_empty_string_schema("inference_request.prompt")
                |> Zoi.nullish()
                |> Zoi.optional(),
              model_preference: Contracts.any_map_schema() |> Zoi.nullish() |> Zoi.optional(),
              target_preference: Contracts.any_map_schema() |> Zoi.nullish() |> Zoi.optional(),
              stream?: Zoi.boolean() |> Zoi.default(false),
              tool_policy: Contracts.any_map_schema() |> Zoi.default(%{}),
              output_constraints: Contracts.any_map_schema() |> Zoi.default(%{}),
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
  def new(%__MODULE__{} = request), do: normalize(request)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs =
      attrs
      |> Map.new()
      |> normalize_messages_attr()

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = request) do
    case normalize(request) do
      {:ok, request} -> request
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, request} -> request
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = request) do
    %{
      "contract_version" => request.contract_version,
      "request_id" => request.request_id,
      "operation" => request.operation,
      "messages" => request.messages,
      "prompt" => request.prompt,
      "model_preference" => request.model_preference,
      "target_preference" => request.target_preference,
      "stream?" => request.stream?,
      "tool_policy" => request.tool_policy,
      "output_constraints" => request.output_constraints,
      "metadata" => request.metadata
    }
    |> Contracts.dump_json_safe!()
  end

  defp normalize(%__MODULE__{} = request) do
    {:ok,
     %__MODULE__{
       request
       | contract_version:
           Contracts.validate_inference_contract_version!(request.contract_version),
         operation: Contracts.validate_inference_operation!(request.operation),
         messages: normalize_messages!(request.messages),
         model_preference: normalize_optional_map(request.model_preference),
         target_preference: normalize_optional_map(request.target_preference),
         tool_policy: normalize_map!(request.tool_policy, "tool_policy"),
         output_constraints: normalize_map!(request.output_constraints, "output_constraints"),
         metadata: normalize_map!(request.metadata, "metadata")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp normalize_messages_attr(attrs) do
    case Contracts.get(attrs, :messages) do
      nil -> attrs
      messages -> Map.put(attrs, :messages, Enum.map(messages, &Map.new/1))
    end
  end

  defp normalize_messages!(messages) when is_list(messages) do
    Enum.map(messages, fn
      %{} = message -> Map.new(message)
      other -> raise ArgumentError, "messages entries must be maps, got: #{inspect(other)}"
    end)
  end

  defp normalize_messages!(messages) do
    raise ArgumentError, "messages must be a list, got: #{inspect(messages)}"
  end

  defp normalize_optional_map(nil), do: nil
  defp normalize_optional_map(%{} = value), do: Map.new(value)

  defp normalize_optional_map(value) do
    raise ArgumentError, "expected an optional map, got: #{inspect(value)}"
  end

  defp normalize_map!(%{} = value, _field_name), do: Map.new(value)

  defp normalize_map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end
end
