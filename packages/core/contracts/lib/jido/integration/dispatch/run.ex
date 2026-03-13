defmodule Jido.Integration.Dispatch.Run do
  @moduledoc """
  Durable execution run record created from a dispatch acceptance.
  """

  @type status :: :accepted | :running | :succeeded | :failed | :dead_lettered

  @type t :: %__MODULE__{
          run_id: String.t(),
          attempt_id: String.t(),
          dispatch_id: String.t(),
          idempotency_key: String.t(),
          tenant_id: String.t() | nil,
          connector_id: String.t() | nil,
          trigger_id: String.t(),
          callback_id: String.t() | nil,
          status: status(),
          attempt: pos_integer(),
          max_attempts: pos_integer(),
          result: map() | nil,
          error_class: String.t() | nil,
          error_context: map() | nil,
          trace_context: map(),
          accepted_at: DateTime.t(),
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil,
          updated_at: DateTime.t(),
          payload: map()
        }

  defstruct [
    :run_id,
    :attempt_id,
    :dispatch_id,
    :idempotency_key,
    :tenant_id,
    :connector_id,
    :trigger_id,
    :callback_id,
    :result,
    :error_class,
    :error_context,
    :accepted_at,
    :started_at,
    :finished_at,
    :updated_at,
    status: :accepted,
    attempt: 1,
    max_attempts: 5,
    trace_context: %{},
    payload: %{}
  ]
end
