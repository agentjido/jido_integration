defmodule Jido.Integration.V2.TriggerRecord do
  @moduledoc """
  Durable trigger admission or rejection record owned by the control plane.
  """

  alias Jido.Integration.V2.Contracts

  @enforce_keys [
    :admission_id,
    :source,
    :connector_id,
    :trigger_id,
    :capability_id,
    :tenant_id,
    :dedupe_key,
    :payload,
    :signal,
    :status
  ]
  defstruct [
    :admission_id,
    :source,
    :connector_id,
    :trigger_id,
    :capability_id,
    :tenant_id,
    :external_id,
    :dedupe_key,
    :partition_key,
    :payload,
    :signal,
    :status,
    :run_id,
    :rejection_reason,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          admission_id: String.t(),
          source: Contracts.trigger_source(),
          connector_id: String.t(),
          trigger_id: String.t(),
          capability_id: String.t(),
          tenant_id: String.t(),
          external_id: String.t() | nil,
          dedupe_key: String.t(),
          partition_key: String.t() | nil,
          payload: map(),
          signal: map(),
          status: Contracts.trigger_status(),
          run_id: String.t() | nil,
          rejection_reason: term() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    inserted_at = Map.get(attrs, :inserted_at, Contracts.now())

    struct!(__MODULE__, %{
      admission_id: Map.get(attrs, :admission_id, Contracts.next_id("trigger")),
      source: Contracts.validate_trigger_source!(Map.fetch!(attrs, :source)),
      connector_id:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :connector_id), "connector_id"),
      trigger_id:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :trigger_id), "trigger_id"),
      capability_id:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :capability_id), "capability_id"),
      tenant_id: Contracts.validate_non_empty_string!(Map.fetch!(attrs, :tenant_id), "tenant_id"),
      external_id: Map.get(attrs, :external_id),
      dedupe_key:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :dedupe_key), "dedupe_key"),
      partition_key: Map.get(attrs, :partition_key),
      payload: Map.get(attrs, :payload, %{}),
      signal: Map.get(attrs, :signal, %{}),
      status: Contracts.validate_trigger_status!(Map.get(attrs, :status, :accepted)),
      run_id: Map.get(attrs, :run_id),
      rejection_reason: Map.get(attrs, :rejection_reason),
      inserted_at: inserted_at,
      updated_at: Map.get(attrs, :updated_at, inserted_at)
    })
  end
end
