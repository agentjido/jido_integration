defmodule Jido.Integration.V2.StorePostgres.Schemas.TriggerRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:admission_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "trigger_records" do
    field(:tenant_id, :string)
    field(:connector_id, :string)
    field(:trigger_id, :string)
    field(:capability_id, :string)
    field(:source, Ecto.Enum, values: [:webhook, :poll])
    field(:external_id, :string)
    field(:dedupe_key, :string)
    field(:partition_key, :string)
    field(:payload, :map)
    field(:signal, :map)
    field(:status, Ecto.Enum, values: [:accepted, :rejected])
    field(:run_id, :string)
    field(:rejection_reason, :binary)

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :admission_id,
      :tenant_id,
      :connector_id,
      :trigger_id,
      :capability_id,
      :source,
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
    ])
    |> validate_required([
      :admission_id,
      :tenant_id,
      :connector_id,
      :trigger_id,
      :capability_id,
      :source,
      :dedupe_key,
      :payload,
      :signal,
      :status,
      :inserted_at,
      :updated_at
    ])
  end
end
