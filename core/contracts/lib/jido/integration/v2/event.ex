defmodule Jido.Integration.V2.Event do
  @moduledoc """
  Canonical append-only event for run and attempt observation.
  """

  alias Jido.Integration.V2.Contracts

  @enforce_keys [:event_id, :schema_version, :run_id, :seq, :type, :stream, :level, :trace, :ts]
  defstruct [
    :event_id,
    :schema_version,
    :run_id,
    :attempt,
    :attempt_id,
    :seq,
    :type,
    :stream,
    :level,
    :payload,
    :payload_ref,
    :trace,
    :target_id,
    :session_id,
    :runtime_ref_id,
    :ts
  ]

  @type t :: %__MODULE__{
          event_id: String.t(),
          schema_version: String.t(),
          run_id: String.t(),
          attempt: pos_integer() | nil,
          attempt_id: String.t() | nil,
          seq: non_neg_integer(),
          type: String.t(),
          stream: Contracts.event_stream(),
          level: Contracts.event_level(),
          payload: map(),
          payload_ref: Contracts.payload_ref() | nil,
          trace: Contracts.trace_context(),
          target_id: String.t() | nil,
          session_id: String.t() | nil,
          runtime_ref_id: String.t() | nil,
          ts: DateTime.t()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    run_id = Map.fetch!(attrs, :run_id)
    {attempt, attempt_id} = normalize_attempt_identity(run_id, attrs)

    struct!(__MODULE__, %{
      event_id: Map.get(attrs, :event_id, Contracts.next_id("event")),
      schema_version: Map.get(attrs, :schema_version, Contracts.schema_version()),
      run_id: run_id,
      attempt: attempt,
      attempt_id: attempt_id,
      seq: Contracts.validate_event_seq!(Map.fetch!(attrs, :seq)),
      type: Map.fetch!(attrs, :type),
      stream: Contracts.validate_event_stream!(Map.get(attrs, :stream, :system)),
      level: Contracts.validate_event_level!(Map.get(attrs, :level, :info)),
      payload: Map.get(attrs, :payload, %{}),
      payload_ref: normalize_payload_ref(Map.get(attrs, :payload_ref)),
      trace: Contracts.normalize_trace(Map.get(attrs, :trace, %{})),
      target_id: Map.get(attrs, :target_id),
      session_id: Map.get(attrs, :session_id),
      runtime_ref_id: Map.get(attrs, :runtime_ref_id),
      ts: Map.get(attrs, :ts, Contracts.now())
    })
  end

  defp normalize_attempt_identity(run_id, attrs) do
    case {Map.get(attrs, :attempt), Map.get(attrs, :attempt_id)} do
      {nil, nil} ->
        {nil, nil}

      {attempt, nil} ->
        attempt = Contracts.validate_attempt!(attempt)
        {attempt, Contracts.attempt_id(run_id, attempt)}

      {nil, attempt_id} ->
        attempt = Contracts.attempt_from_id!(run_id, attempt_id)
        {attempt, attempt_id}

      {attempt, attempt_id} ->
        attempt = Contracts.validate_attempt!(attempt)
        expected_attempt_id = Contracts.attempt_id(run_id, attempt)

        if attempt_id != expected_attempt_id do
          raise ArgumentError,
                "event attempt_id must match run_id and attempt: #{inspect({run_id, attempt, attempt_id})}"
        end

        {attempt, attempt_id}
    end
  end

  defp normalize_payload_ref(nil), do: nil
  defp normalize_payload_ref(payload_ref), do: Contracts.normalize_payload_ref!(payload_ref)
end
