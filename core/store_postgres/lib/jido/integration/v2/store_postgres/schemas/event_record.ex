defmodule Jido.Integration.V2.StorePostgres.Schemas.EventRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]

  schema "run_events" do
    field(:event_id, :string)
    field(:run_id, :string)
    field(:attempt, :integer)
    field(:attempt_id, :string)
    field(:attempt_key, :string)
    field(:seq, :integer)
    field(:schema_version, :string)
    field(:type, :string)
    field(:stream, Ecto.Enum, values: [:assistant, :stdout, :stderr, :system, :control])
    field(:level, Ecto.Enum, values: [:debug, :info, :warn, :error])
    field(:payload, :map)
    field(:payload_ref, :map)
    field(:trace, :map)
    field(:target_id, :string)
    field(:session_id, :string)
    field(:runtime_ref_id, :string)
    field(:ts, :utc_datetime_usec)

    timestamps(updated_at: false)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :event_id,
      :run_id,
      :attempt,
      :attempt_id,
      :attempt_key,
      :seq,
      :schema_version,
      :type,
      :stream,
      :level,
      :payload,
      :payload_ref,
      :trace,
      :target_id,
      :session_id,
      :runtime_ref_id,
      :ts,
      :inserted_at
    ])
    |> validate_required([
      :event_id,
      :run_id,
      :attempt_key,
      :seq,
      :schema_version,
      :type,
      :stream,
      :level,
      :payload,
      :trace,
      :ts
    ])
    |> unique_constraint(:seq, name: :run_events_position_index)
    |> unique_constraint(:event_id, name: :run_events_event_id_index)
  end
end
