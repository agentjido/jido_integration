defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.HardenSubmissionDedupeRetention do
  use Ecto.Migration

  def change do
    alter table(:submission_records) do
      add :tenant_id, :text
      add :submission_dedupe_key, :text
      add :last_seen_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
    end

    create unique_index(:submission_records, [:tenant_id, :submission_dedupe_key],
             name: :submission_records_tenant_dedupe_live_index
           )

    create index(:submission_records, [:expires_at],
             name: :submission_records_expiry_index
           )

    create table(:expired_submission_records) do
      add :submission_key, :text, null: false
      add :tenant_id, :text, null: false
      add :submission_dedupe_key, :text, null: false
      add :identity_checksum, :text, null: false
      add :status, :text, null: false
      add :acceptance_json, :map
      add :rejection_json, :map
      add :last_seen_at, :utc_datetime_usec, null: false
      add :expired_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:expired_submission_records, [:tenant_id, :submission_dedupe_key],
             name: :expired_submission_records_tenant_dedupe_index
           )
  end
end
