defmodule Jido.Integration.V2.RuntimeResult do
  @moduledoc """
  Shared runtime emission envelope for direct, session, and stream execution.
  """

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @event_schema Contracts.strict_object!(
                  type: Contracts.non_empty_string_schema("runtime_result.events.type"),
                  stream:
                    Contracts.enumish_schema(
                      [:assistant, :stdout, :stderr, :system, :control],
                      "runtime_result.events.stream"
                    )
                    |> Zoi.default(:system),
                  level:
                    Contracts.enumish_schema(
                      [:debug, :info, :warn, :error],
                      "runtime_result.events.level"
                    )
                    |> Zoi.default(:info),
                  payload: Contracts.map_schema("event payload") |> Zoi.default(%{}),
                  payload_ref:
                    Contracts.payload_ref_schema("runtime_result.events.payload_ref")
                    |> Zoi.nullish()
                    |> Zoi.optional(),
                  trace: Contracts.map_schema("event trace") |> Zoi.default(%{}),
                  target_id:
                    Contracts.non_empty_string_schema("runtime_result.events.target_id")
                    |> Zoi.nullish()
                    |> Zoi.optional(),
                  session_id:
                    Contracts.non_empty_string_schema("runtime_result.events.session_id")
                    |> Zoi.nullish()
                    |> Zoi.optional(),
                  runtime_ref_id:
                    Contracts.non_empty_string_schema("runtime_result.events.runtime_ref_id")
                    |> Zoi.nullish()
                    |> Zoi.optional()
                )

  @schema Zoi.struct(
            __MODULE__,
            %{
              output: Contracts.map_schema("output") |> Zoi.nullish(),
              runtime_ref_id:
                Contracts.non_empty_string_schema("runtime_result.runtime_ref_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              events: Zoi.list(@event_schema) |> Zoi.default([]),
              artifacts:
                Zoi.list(Contracts.struct_schema(ArtifactRef, "runtime_result.artifacts"))
                |> Zoi.default([])
            },
            coerce: true
          )

  @type event_spec :: %{
          required(:type) => String.t(),
          optional(:stream) => Contracts.event_stream(),
          optional(:level) => Contracts.event_level(),
          optional(:payload) => map(),
          optional(:payload_ref) => Contracts.payload_ref(),
          optional(:trace) => Contracts.trace_context(),
          optional(:target_id) => String.t(),
          optional(:session_id) => String.t(),
          optional(:runtime_ref_id) => String.t()
        }
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = runtime_result), do: {:ok, normalize(runtime_result)}

  def new(attrs) do
    case Schema.new(__MODULE__, @schema, attrs) do
      {:ok, runtime_result} -> {:ok, normalize(runtime_result)}
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = runtime_result), do: normalize(runtime_result)

  def new!(attrs) do
    case new(attrs) do
      {:ok, runtime_result} -> runtime_result
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  defp normalize(%__MODULE__{} = runtime_result) do
    %__MODULE__{
      runtime_result
      | events: Enum.map(runtime_result.events, &normalize_event!/1)
    }
  end

  defp normalize_event!(event) when is_map(event) do
    event
    |> Map.new()
    |> Map.put(:trace, Contracts.normalize_trace(Contracts.get(event, :trace, %{})))
    |> maybe_put(:payload_ref, normalize_payload_ref(Contracts.get(event, :payload_ref)))
    |> maybe_put(
      :target_id,
      normalize_optional_string(Contracts.get(event, :target_id), "target_id")
    )
    |> maybe_put(
      :session_id,
      normalize_optional_string(Contracts.get(event, :session_id), "session_id")
    )
    |> maybe_put(
      :runtime_ref_id,
      normalize_optional_string(Contracts.get(event, :runtime_ref_id), "runtime_ref_id")
    )
  end

  defp normalize_payload_ref(nil), do: nil
  defp normalize_payload_ref(payload_ref), do: Contracts.normalize_payload_ref!(payload_ref)

  defp normalize_optional_string(nil, _field_name), do: nil

  defp normalize_optional_string(value, field_name) do
    Contracts.validate_non_empty_string!(value, field_name)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
