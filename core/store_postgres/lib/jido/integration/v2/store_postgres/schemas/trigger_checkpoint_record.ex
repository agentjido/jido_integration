defmodule Jido.Integration.V2.StorePostgres.Schemas.TriggerCheckpointRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, inserted_at: false]

  schema "trigger_checkpoints" do
    field(:tenant_id, :string)
    field(:connector_id, :string)
    field(:trigger_id, :string)
    field(:partition_key, :string)
    field(:cursor, :string)
    field(:last_event_id, :string)
    field(:last_event_time, :utc_datetime_usec)
    field(:revision, :integer)

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :tenant_id,
      :connector_id,
      :trigger_id,
      :partition_key,
      :cursor,
      :last_event_id,
      :last_event_time,
      :revision,
      :updated_at
    ])
    |> validate_required([
      :tenant_id,
      :connector_id,
      :trigger_id,
      :partition_key,
      :cursor,
      :revision,
      :updated_at
    ])
    |> unique_constraint(:partition_key, name: :trigger_checkpoints_scope_index)
  end
end
