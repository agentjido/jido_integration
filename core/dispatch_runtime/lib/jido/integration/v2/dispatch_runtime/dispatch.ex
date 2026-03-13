defmodule Jido.Integration.V2.DispatchRuntime.Dispatch do
  @moduledoc """
  Durable transport-state record for async trigger execution.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  @type status ::
          :queued
          | :running
          | :retry_scheduled
          | :completed
          | :dead_lettered

  @enforce_keys [
    :dispatch_id,
    :trigger,
    :status,
    :max_attempts,
    :attempts,
    :inserted_at,
    :updated_at
  ]
  defstruct [
    :dispatch_id,
    :trigger,
    :checkpoint,
    :status,
    :run_id,
    :max_attempts,
    :attempts,
    :available_at,
    :last_error,
    :completed_at,
    :dead_lettered_at,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          dispatch_id: String.t(),
          trigger: TriggerRecord.t(),
          checkpoint: TriggerCheckpoint.t() | nil,
          status: status(),
          run_id: String.t() | nil,
          max_attempts: pos_integer(),
          attempts: non_neg_integer(),
          available_at: DateTime.t() | nil,
          last_error: map() | nil,
          completed_at: DateTime.t() | nil,
          dead_lettered_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    timestamp = Map.get(attrs, :inserted_at, Contracts.now())

    struct!(__MODULE__, %{
      dispatch_id: Map.fetch!(attrs, :dispatch_id),
      trigger: Map.fetch!(attrs, :trigger),
      checkpoint: Map.get(attrs, :checkpoint),
      status: Map.get(attrs, :status, :queued),
      run_id: Map.get(attrs, :run_id),
      max_attempts: Map.fetch!(attrs, :max_attempts),
      attempts: Map.get(attrs, :attempts, 0),
      available_at: Map.get(attrs, :available_at),
      last_error: Map.get(attrs, :last_error),
      completed_at: Map.get(attrs, :completed_at),
      dead_lettered_at: Map.get(attrs, :dead_lettered_at),
      inserted_at: timestamp,
      updated_at: Map.get(attrs, :updated_at, timestamp)
    })
  end
end
