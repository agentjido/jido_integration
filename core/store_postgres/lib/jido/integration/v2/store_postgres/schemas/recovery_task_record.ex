defmodule Jido.Integration.V2.StorePostgres.Schemas.RecoveryTaskRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:task_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "attempt_recovery_tasks" do
    field(:subject_ref, :string)
    field(:run_id, :string)
    field(:attempt_id, :string)
    field(:route_id, :string)
    field(:receipt_id, :string)
    field(:reason, :string)
    field(:status, Ecto.Enum, values: [:pending, :running, :resolved, :quarantined])
    field(:due_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})
    field(:claim_ref, :string)
    field(:claim_expires_at, :utc_datetime_usec)
    field(:row_version, :integer, default: 1)

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :task_id,
      :subject_ref,
      :run_id,
      :attempt_id,
      :route_id,
      :receipt_id,
      :reason,
      :status,
      :due_at,
      :metadata,
      :claim_ref,
      :claim_expires_at,
      :row_version,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :task_id,
      :subject_ref,
      :reason,
      :status,
      :due_at,
      :metadata,
      :row_version,
      :inserted_at,
      :updated_at
    ])
    |> unique_constraint([:attempt_id, :reason],
      name: :attempt_recovery_tasks_attempt_reason_index
    )
  end
end
