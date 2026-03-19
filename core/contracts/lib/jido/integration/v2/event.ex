defmodule Jido.Integration.V2.Event do
  @moduledoc """
  Canonical append-only event for run and attempt observation.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @streams [:assistant, :stdout, :stderr, :system, :control]
  @levels [:debug, :info, :warn, :error]

  @schema Zoi.struct(
            __MODULE__,
            %{
              event_id:
                Contracts.non_empty_string_schema("event.event_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              schema_version: Zoi.string() |> Zoi.default(Contracts.schema_version()),
              run_id: Contracts.non_empty_string_schema("event.run_id"),
              attempt: Zoi.integer() |> Zoi.min(1) |> Zoi.nullish() |> Zoi.optional(),
              attempt_id:
                Contracts.non_empty_string_schema("event.attempt_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              seq: Zoi.integer() |> Zoi.min(0),
              type: Contracts.non_empty_string_schema("event.type"),
              stream: Contracts.enumish_schema(@streams, "event.stream") |> Zoi.default(:system),
              level: Contracts.enumish_schema(@levels, "event.level") |> Zoi.default(:info),
              payload: Contracts.any_map_schema() |> Zoi.default(%{}),
              payload_ref:
                Contracts.payload_ref_schema("event.payload_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              trace: Contracts.any_map_schema() |> Zoi.default(%{}),
              target_id:
                Contracts.non_empty_string_schema("event.target_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              session_id:
                Contracts.non_empty_string_schema("event.session_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              runtime_ref_id:
                Contracts.non_empty_string_schema("event.runtime_ref_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              ts: Contracts.datetime_schema("event.ts") |> Zoi.nullish() |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = event), do: normalize(event)

  def new(attrs) do
    case Schema.new(__MODULE__, @schema, attrs) do
      {:ok, event} -> normalize(event)
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = event) do
    case normalize(event) do
      {:ok, event} -> event
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, event} -> event
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  defp normalize(%__MODULE__{} = event) do
    with {:ok, attempt, attempt_id} <- normalize_attempt_identity(event.run_id, event) do
      {:ok,
       %__MODULE__{
         event
         | event_id: event.event_id || Contracts.next_id("event"),
           attempt: attempt,
           attempt_id: attempt_id,
           payload_ref: normalize_payload_ref(event.payload_ref),
           trace: Contracts.normalize_trace(event.trace),
           ts: event.ts || Contracts.now()
       }}
    end
  end

  defp normalize_attempt_identity(_run_id, %__MODULE__{attempt: nil, attempt_id: nil}),
    do: {:ok, nil, nil}

  defp normalize_attempt_identity(run_id, %__MODULE__{attempt: attempt, attempt_id: nil}) do
    attempt = Contracts.validate_attempt!(attempt)
    {:ok, attempt, Contracts.attempt_id(run_id, attempt)}
  end

  defp normalize_attempt_identity(run_id, %__MODULE__{attempt: nil, attempt_id: attempt_id}) do
    {:ok, Contracts.attempt_from_id!(run_id, attempt_id), attempt_id}
  end

  defp normalize_attempt_identity(
         run_id,
         %__MODULE__{attempt: attempt, attempt_id: attempt_id}
       ) do
    attempt = Contracts.validate_attempt!(attempt)
    expected_attempt_id = Contracts.attempt_id(run_id, attempt)

    if attempt_id == expected_attempt_id do
      {:ok, attempt, attempt_id}
    else
      {:error,
       ArgumentError.exception(
         "event attempt_id must match run_id and attempt: #{inspect({run_id, attempt, attempt_id})}"
       )}
    end
  end

  defp normalize_payload_ref(nil), do: nil
  defp normalize_payload_ref(payload_ref), do: Contracts.normalize_payload_ref!(payload_ref)
end
