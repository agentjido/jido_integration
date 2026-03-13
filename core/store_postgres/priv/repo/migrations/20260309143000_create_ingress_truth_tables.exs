defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.CreateIngressTruthTables do
  use Ecto.Migration

  def change do
    create table(:trigger_checkpoints, primary_key: false) do
      add(:tenant_id, :text, null: false)
      add(:connector_id, :text, null: false)
      add(:trigger_id, :text, null: false)
      add(:partition_key, :text, null: false)
      add(:cursor, :text, null: false)
      add(:last_event_id, :text)
      add(:last_event_time, :utc_datetime_usec)
      add(:revision, :integer, null: false, default: 1)

      timestamps(type: :utc_datetime_usec, inserted_at: false)
    end

    create(
      unique_index(
        :trigger_checkpoints,
        [:tenant_id, :connector_id, :trigger_id, :partition_key],
        name: :trigger_checkpoints_scope_index
      )
    )

    create(index(:trigger_checkpoints, [:tenant_id, :connector_id, :trigger_id, :updated_at]))

    create table(:dedupe_keys, primary_key: false) do
      add(:tenant_id, :text, null: false)
      add(:connector_id, :text, null: false)
      add(:trigger_id, :text, null: false)
      add(:dedupe_key, :text, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :dedupe_keys,
        [:tenant_id, :connector_id, :trigger_id, :dedupe_key],
        name: :dedupe_keys_scope_index
      )
    )

    create(index(:dedupe_keys, [:expires_at]))

    create table(:trigger_records, primary_key: false) do
      add(:admission_id, :text, primary_key: true)
      add(:tenant_id, :text, null: false)
      add(:connector_id, :text, null: false)
      add(:trigger_id, :text, null: false)
      add(:capability_id, :text, null: false)
      add(:source, :text, null: false)
      add(:external_id, :text)
      add(:dedupe_key, :text, null: false)
      add(:partition_key, :text)
      add(:payload, :map, null: false, default: %{})
      add(:signal, :map, null: false, default: %{})
      add(:status, :text, null: false)
      add(:run_id, references(:runs, column: :run_id, type: :text, on_delete: :nilify_all))
      add(:rejection_reason, :binary)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:trigger_records, [:tenant_id, :connector_id, :trigger_id, :dedupe_key]))
    create(index(:trigger_records, [:run_id]))
    create(index(:trigger_records, [:status, :inserted_at]))
  end
end
