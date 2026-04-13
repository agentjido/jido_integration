defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.CreateSubmissionRecords do
  use Ecto.Migration

  def change do
    create table(:submission_records, primary_key: false) do
      add(:submission_key, :text, primary_key: true)
      add(:identity_checksum, :text, null: false)
      add(:status, :text, null: false)
      add(:acceptance_json, :map)
      add(:rejection_json, :map)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:submission_records, [:status, :updated_at]))
  end
end
