defmodule Jido.Integration.Trigger.Event do
  @moduledoc """
  Normalized trigger event envelope.
  """

  @type t :: %__MODULE__{
          trigger_id: String.t() | nil,
          event_id: String.t(),
          event_time: DateTime.t(),
          received_at: DateTime.t(),
          tenant_id: String.t() | nil,
          connector_id: String.t() | nil,
          connection_id: String.t() | nil,
          resource_key: String.t() | nil,
          payload: map(),
          raw: binary() | nil,
          dedupe_key: String.t(),
          checkpoint: map() | nil,
          trace: map()
        }

  defstruct [
    :trigger_id,
    :event_id,
    :event_time,
    :received_at,
    :tenant_id,
    :connector_id,
    :connection_id,
    :resource_key,
    :raw,
    :dedupe_key,
    :checkpoint,
    payload: %{},
    trace: %{}
  ]
end
