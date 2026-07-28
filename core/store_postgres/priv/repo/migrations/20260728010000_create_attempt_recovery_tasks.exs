defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.CreateAttemptRecoveryTasks do
  use Ecto.Migration

  def change do
    create table(:attempt_recovery_tasks, primary_key: false) do
      add(:task_id, :text, primary_key: true)
      add(:subject_ref, :text, null: false)

      add(
        :run_id,
        references(:runs, column: :run_id, type: :text, on_delete: :delete_all)
      )

      add(
        :attempt_id,
        references(:run_attempts, column: :attempt_id, type: :text, on_delete: :delete_all)
      )

      add(:route_id, :text)
      add(:receipt_id, :text)
      add(:reason, :text, null: false)
      add(:status, :text, null: false)
      add(:due_at, :utc_datetime_usec, null: false)
      add(:metadata, :map, null: false, default: %{})
      add(:claim_ref, :text)
      add(:claim_expires_at, :utc_datetime_usec)
      add(:row_version, :bigint, null: false, default: 1)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:attempt_recovery_tasks, [:attempt_id, :reason],
        name: :attempt_recovery_tasks_attempt_reason_index
      )
    )

    create(index(:attempt_recovery_tasks, [:status, :due_at]))
    create(index(:attempt_recovery_tasks, [:claim_expires_at]))
  end
end
