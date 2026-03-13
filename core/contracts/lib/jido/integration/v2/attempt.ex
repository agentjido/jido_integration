defmodule Jido.Integration.V2.Attempt do
  @moduledoc """
  One concrete execution attempt of a run.
  """

  alias Jido.Integration.V2.Contracts

  @enforce_keys [:attempt_id, :run_id, :runtime_class, :status]
  defstruct [
    :attempt_id,
    :run_id,
    :attempt,
    :aggregator_id,
    :aggregator_epoch,
    :runtime_class,
    :status,
    :credential_lease_id,
    :target_id,
    :runtime_ref_id,
    :output,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          attempt_id: String.t(),
          run_id: String.t(),
          attempt: pos_integer(),
          aggregator_id: String.t(),
          aggregator_epoch: pos_integer(),
          runtime_class: Contracts.runtime_class(),
          status: Contracts.attempt_status(),
          credential_lease_id: String.t() | nil,
          target_id: String.t() | nil,
          runtime_ref_id: String.t() | nil,
          output: map() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    timestamp = Map.get(attrs, :inserted_at, Contracts.now())
    run_id = Map.fetch!(attrs, :run_id)
    attempt = Contracts.validate_attempt!(Map.fetch!(attrs, :attempt))
    attempt_id = Map.get(attrs, :attempt_id, Contracts.attempt_id(run_id, attempt))

    if attempt_id != Contracts.attempt_id(run_id, attempt) do
      raise ArgumentError,
            "attempt_id must match run_id and attempt: #{inspect({run_id, attempt, attempt_id})}"
    end

    struct!(__MODULE__, %{
      attempt_id: attempt_id,
      run_id: run_id,
      attempt: attempt,
      aggregator_id: Map.get(attrs, :aggregator_id, "control_plane"),
      aggregator_epoch:
        Contracts.validate_aggregator_epoch!(Map.get(attrs, :aggregator_epoch, 1)),
      runtime_class: Contracts.validate_runtime_class!(Map.fetch!(attrs, :runtime_class)),
      status: Contracts.validate_attempt_status!(Map.get(attrs, :status, :accepted)),
      credential_lease_id: Map.get(attrs, :credential_lease_id),
      target_id: Map.get(attrs, :target_id),
      runtime_ref_id: Map.get(attrs, :runtime_ref_id),
      output: Map.get(attrs, :output),
      inserted_at: timestamp,
      updated_at: Map.get(attrs, :updated_at, timestamp)
    })
  end
end
