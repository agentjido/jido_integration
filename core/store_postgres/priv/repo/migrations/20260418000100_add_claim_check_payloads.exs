defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.AddClaimCheckPayloads do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add(:input_payload_ref, :map)
      add(:result_payload_ref, :map)
    end

    alter table(:run_attempts) do
      add(:output_payload_ref, :map)
    end

    create table(:claim_check_blobs) do
      add(:store, :string, null: false)
      add(:key, :string, null: false)
      add(:checksum, :string, null: false)
      add(:size_bytes, :bigint, null: false)
      add(:content_type, :string, null: false)
      add(:redaction_class, :string, null: false)
      add(:status, :string, null: false, default: "staged")
      add(:trace_id, :string)
      add(:payload_kind, :string)
      add(:staged_at, :utc_datetime_usec, null: false)
      add(:referenced_at, :utc_datetime_usec)
      add(:deleted_at, :utc_datetime_usec)

      timestamps()
    end

    create(
      unique_index(:claim_check_blobs, [:store, :key], name: :claim_check_blobs_store_key_index)
    )

    create(index(:claim_check_blobs, [:status]))
    create(index(:claim_check_blobs, [:referenced_at]))

    create table(:claim_check_references) do
      add(:store, :string, null: false)
      add(:key, :string, null: false)
      add(:ledger_kind, :string, null: false)
      add(:ledger_id, :string, null: false)
      add(:payload_field, :string, null: false)
      add(:run_id, :string)
      add(:attempt_id, :string)
      add(:event_id, :string)
      add(:trace_id, :string)

      timestamps(updated_at: false)
    end

    create(index(:claim_check_references, [:store, :key]))

    create(
      unique_index(
        :claim_check_references,
        [:ledger_kind, :ledger_id, :payload_field],
        name: :claim_check_references_ledger_identity_index
      )
    )
  end
end
