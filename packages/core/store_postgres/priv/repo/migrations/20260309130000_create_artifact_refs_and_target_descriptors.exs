defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.CreateArtifactRefsAndTargetDescriptors do
  use Ecto.Migration

  def change do
    create table(:artifact_refs, primary_key: false) do
      add(:artifact_id, :text, primary_key: true)

      add(:run_id, references(:runs, column: :run_id, type: :text, on_delete: :delete_all),
        null: false
      )

      add(
        :attempt_id,
        references(:run_attempts, column: :attempt_id, type: :text, on_delete: :delete_all),
        null: false
      )

      add(:artifact_type, :text, null: false)
      add(:transport_mode, :text, null: false)
      add(:checksum, :text, null: false)
      add(:size_bytes, :bigint, null: false)
      add(:payload_ref, :map, null: false)
      add(:retention_class, :text, null: false)
      add(:redaction_status, :text, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:artifact_refs, [:run_id]))
    create(index(:artifact_refs, [:attempt_id]))
    create(index(:artifact_refs, [:checksum]))

    create table(:target_descriptors, primary_key: false) do
      add(:target_id, :text, primary_key: true)
      add(:capability_id, :text, null: false)
      add(:runtime_class, :text, null: false)
      add(:version, :text, null: false)
      add(:features, :map, null: false, default: %{})
      add(:constraints, :map, null: false, default: %{})
      add(:health, :text, null: false)
      add(:location, :map, null: false, default: %{})
      add(:extensions, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:target_descriptors, [:capability_id, :runtime_class]))
  end
end
