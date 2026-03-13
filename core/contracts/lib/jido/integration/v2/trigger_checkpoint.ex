defmodule Jido.Integration.V2.TriggerCheckpoint do
  @moduledoc """
  Durable checkpoint for polling-style trigger progression.
  """

  alias Jido.Integration.V2.Contracts

  @enforce_keys [:tenant_id, :connector_id, :trigger_id, :partition_key, :cursor]
  defstruct [
    :tenant_id,
    :connector_id,
    :trigger_id,
    :partition_key,
    :cursor,
    :last_event_id,
    :last_event_time,
    :revision,
    :updated_at
  ]

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          connector_id: String.t(),
          trigger_id: String.t(),
          partition_key: String.t(),
          cursor: String.t(),
          last_event_id: String.t() | nil,
          last_event_time: DateTime.t() | nil,
          revision: pos_integer(),
          updated_at: DateTime.t()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    updated_at = Map.get(attrs, :updated_at, Contracts.now())

    struct!(__MODULE__, %{
      tenant_id: Contracts.validate_non_empty_string!(Map.fetch!(attrs, :tenant_id), "tenant_id"),
      connector_id:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :connector_id), "connector_id"),
      trigger_id:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :trigger_id), "trigger_id"),
      partition_key:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :partition_key), "partition_key"),
      cursor: Contracts.validate_non_empty_string!(Map.fetch!(attrs, :cursor), "cursor"),
      last_event_id: Map.get(attrs, :last_event_id),
      last_event_time: Map.get(attrs, :last_event_time),
      revision: Map.get(attrs, :revision, 1),
      updated_at: updated_at
    })
  end
end
