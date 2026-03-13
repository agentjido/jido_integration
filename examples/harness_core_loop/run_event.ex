defmodule Jido.Integration.Examples.HarnessCore.RunEvent do
  @moduledoc """
  Run event — the canonical event envelope for the harness core loop.

  Every state transition in a dispatched run produces an immutable event.
  Events are ordered by `(run_id, attempt_id, seq)` and deduplicated
  by the aggregator using that triple as a natural key.

  ## Event Types

  - `:dispatch_started` — adapter execution began
  - `:dispatch_succeeded` — adapter returned success
  - `:dispatch_failed` — adapter returned an error
  - `:policy_denied` — gateway policy blocked the dispatch
  - `:target_rejected` — target compatibility check failed (version/capability mismatch)
  """

  @type event_type ::
          :dispatch_started
          | :dispatch_succeeded
          | :dispatch_failed
          | :policy_denied
          | :target_rejected

  @type t :: %__MODULE__{
          run_id: String.t(),
          attempt_id: pos_integer(),
          seq: pos_integer(),
          event_type: event_type(),
          payload: map(),
          timestamp: DateTime.t(),
          connector_id: String.t() | nil,
          operation_id: String.t() | nil
        }

  @enforce_keys [:run_id, :attempt_id, :seq, :event_type]
  defstruct [
    :run_id,
    :attempt_id,
    :seq,
    :event_type,
    :connector_id,
    :operation_id,
    payload: %{},
    timestamp: nil
  ]

  @doc "Create a new run event."
  @spec new(keyword()) :: t()
  def new(attrs) do
    %__MODULE__{
      run_id: Keyword.fetch!(attrs, :run_id),
      attempt_id: Keyword.get(attrs, :attempt_id, 1),
      seq: Keyword.fetch!(attrs, :seq),
      event_type: Keyword.fetch!(attrs, :event_type),
      payload: Keyword.get(attrs, :payload, %{}),
      timestamp: DateTime.utc_now(),
      connector_id: Keyword.get(attrs, :connector_id),
      operation_id: Keyword.get(attrs, :operation_id)
    }
  end

  @doc "Returns the dedup key for this event."
  @spec dedup_key(t()) :: {String.t(), pos_integer(), pos_integer()}
  def dedup_key(%__MODULE__{} = event) do
    {event.run_id, event.attempt_id, event.seq}
  end
end
