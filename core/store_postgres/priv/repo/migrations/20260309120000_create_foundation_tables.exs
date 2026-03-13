defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.CreateFoundationTables do
  use Ecto.Migration

  def change do
    create table(:runs, primary_key: false) do
      add(:run_id, :text, primary_key: true)
      add(:capability_id, :text, null: false)
      add(:runtime_class, :text, null: false)
      add(:status, :text, null: false)
      add(:input, :map, null: false)
      add(:credential_ref, :map, null: false)
      add(:target_id, :text)
      add(:result, :map)
      add(:artifact_refs, {:array, :map}, default: [])

      timestamps(type: :utc_datetime_usec)
    end

    create table(:run_attempts, primary_key: false) do
      add(:attempt_id, :text, primary_key: true)

      add(:run_id, references(:runs, column: :run_id, type: :text, on_delete: :delete_all),
        null: false
      )

      add(:attempt, :integer, null: false)
      add(:aggregator_id, :text, null: false)
      add(:aggregator_epoch, :bigint, null: false, default: 1)
      add(:runtime_class, :text, null: false)
      add(:status, :text, null: false)
      add(:credential_lease_id, :text)
      add(:target_id, :text)
      add(:runtime_ref_id, :text)
      add(:output, :map)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:run_attempts, [:run_id, :attempt], name: :run_attempts_run_id_attempt_index)
    )

    create table(:run_events) do
      add(:event_id, :text, null: false)

      add(:run_id, references(:runs, column: :run_id, type: :text, on_delete: :delete_all),
        null: false
      )

      add(:attempt, :integer)

      add(
        :attempt_id,
        references(:run_attempts, column: :attempt_id, type: :text, on_delete: :delete_all)
      )

      add(:attempt_key, :text, null: false)
      add(:seq, :bigint, null: false)
      add(:schema_version, :text, null: false)
      add(:type, :text, null: false)
      add(:stream, :text, null: false)
      add(:level, :text, null: false)
      add(:payload, :map, null: false, default: %{})
      add(:payload_ref, :map)
      add(:trace, :map, null: false, default: %{})
      add(:target_id, :text)
      add(:session_id, :text)
      add(:runtime_ref_id, :text)
      add(:ts, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:run_events, [:run_id, :attempt_key, :seq], name: :run_events_position_index)
    )

    create(unique_index(:run_events, [:event_id], name: :run_events_event_id_index))
    create(index(:run_events, [:run_id, :attempt, :seq]))

    create table(:credentials, primary_key: false) do
      add(:id, :text, primary_key: true)
      add(:subject, :text, null: false)
      add(:scopes, {:array, :text}, null: false, default: [])
      add(:tokens, :map, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create table(:credential_leases, primary_key: false) do
      add(:lease_id, :text, primary_key: true)

      add(
        :credential_ref_id,
        references(:credentials, column: :id, type: :text, on_delete: :delete_all),
        null: false
      )

      add(:subject, :text, null: false)
      add(:scopes, {:array, :text}, null: false, default: [])
      add(:grant, :map, null: false)
      add(:issued_at, :utc_datetime_usec, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:credential_leases, [:credential_ref_id]))
    create(index(:credential_leases, [:expires_at]))

    create table(:connections, primary_key: false) do
      add(:connection_id, :text, primary_key: true)
      add(:subject, :text)
      add(:connector, :text)
      add(:state, :text)
      add(:data, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create table(:install_sessions, primary_key: false) do
      add(:install_session_id, :text, primary_key: true)
      add(:subject, :text)
      add(:connector, :text)
      add(:data, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end
  end
end
