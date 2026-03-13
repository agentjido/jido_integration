defmodule Jido.Integration.Dispatch.Record do
  @moduledoc """
  Durable dispatch transport record.
  """

  @type status :: :queued | :delivered | :failed | :dead_lettered

  @type t :: %__MODULE__{
          dispatch_id: String.t(),
          idempotency_key: String.t(),
          tenant_id: String.t() | nil,
          connector_id: String.t() | nil,
          trigger_id: String.t(),
          event_id: String.t() | nil,
          dedupe_key: String.t() | nil,
          workflow_selector: String.t(),
          payload: map(),
          status: status(),
          attempts: non_neg_integer(),
          max_dispatch_attempts: pos_integer(),
          run_id: String.t() | nil,
          trace_context: map(),
          error_context: map() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :dispatch_id,
    :idempotency_key,
    :tenant_id,
    :connector_id,
    :trigger_id,
    :event_id,
    :dedupe_key,
    :workflow_selector,
    :run_id,
    :error_context,
    :created_at,
    :updated_at,
    payload: %{},
    status: :queued,
    attempts: 0,
    max_dispatch_attempts: 5,
    trace_context: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) do
    now = DateTime.utc_now()

    %__MODULE__{
      dispatch_id: Map.fetch!(attrs, :dispatch_id),
      idempotency_key: Map.fetch!(attrs, :idempotency_key),
      tenant_id: Map.get(attrs, :tenant_id),
      connector_id: Map.get(attrs, :connector_id),
      trigger_id: Map.fetch!(attrs, :trigger_id),
      event_id: Map.get(attrs, :event_id),
      dedupe_key: Map.get(attrs, :dedupe_key),
      workflow_selector: Map.get(attrs, :workflow_selector, Map.fetch!(attrs, :trigger_id)),
      payload: Map.get(attrs, :payload, %{}),
      status: Map.get(attrs, :status, :queued),
      attempts: Map.get(attrs, :attempts, 0),
      max_dispatch_attempts: Map.get(attrs, :max_dispatch_attempts, 5),
      run_id: Map.get(attrs, :run_id),
      trace_context: Map.get(attrs, :trace_context, %{}),
      error_context: Map.get(attrs, :error_context),
      created_at: Map.get(attrs, :created_at, now),
      updated_at: Map.get(attrs, :updated_at, now)
    }
  end
end
