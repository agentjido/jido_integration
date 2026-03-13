defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.ReworkAuthLifecycleTables do
  use Ecto.Migration

  def change do
    drop_if_exists(table(:credential_leases))
    drop_if_exists(table(:install_sessions))
    drop_if_exists(table(:connections))
    drop_if_exists(table(:credentials))

    create table(:credentials, primary_key: false) do
      add(:id, :text, primary_key: true)
      add(:connection_id, :text, null: false)
      add(:subject, :text, null: false)
      add(:auth_type, :text, null: false)
      add(:scopes, {:array, :text}, null: false, default: [])
      add(:lease_fields, {:array, :text}, null: false, default: [])
      add(:secret_envelope, :map, null: false)
      add(:expires_at, :utc_datetime_usec)
      add(:revoked_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:credentials, [:connection_id]))

    create table(:connections, primary_key: false) do
      add(:connection_id, :text, primary_key: true)
      add(:tenant_id, :text, null: false)
      add(:connector_id, :text, null: false)
      add(:auth_type, :text, null: false)
      add(:subject, :text, null: false)
      add(:state, :text, null: false)
      add(:credential_ref_id, :text)
      add(:install_id, :text)
      add(:requested_scopes, {:array, :text}, null: false, default: [])
      add(:granted_scopes, {:array, :text}, null: false, default: [])
      add(:lease_fields, {:array, :text}, null: false, default: [])
      add(:token_expires_at, :utc_datetime_usec)
      add(:last_rotated_at, :utc_datetime_usec)
      add(:revoked_at, :utc_datetime_usec)
      add(:revocation_reason, :text)
      add(:actor_id, :text)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:connections, [:tenant_id, :connector_id]))
    create(index(:connections, [:credential_ref_id]))

    create table(:install_sessions, primary_key: false) do
      add(:install_id, :text, primary_key: true)
      add(:connection_id, :text, null: false)
      add(:tenant_id, :text, null: false)
      add(:connector_id, :text, null: false)
      add(:actor_id, :text, null: false)
      add(:auth_type, :text, null: false)
      add(:subject, :text, null: false)
      add(:state, :text, null: false)
      add(:callback_token, :text, null: false)
      add(:requested_scopes, {:array, :text}, null: false, default: [])
      add(:granted_scopes, {:array, :text}, null: false, default: [])
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:completed_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:install_sessions, [:connection_id]))
    create(index(:install_sessions, [:tenant_id, :connector_id]))

    create table(:credential_leases, primary_key: false) do
      add(:lease_id, :text, primary_key: true)

      add(
        :credential_ref_id,
        references(:credentials, column: :id, type: :text, on_delete: :delete_all),
        null: false
      )

      add(:connection_id, :text, null: false)
      add(:subject, :text, null: false)
      add(:scopes, {:array, :text}, null: false, default: [])
      add(:payload_keys, {:array, :text}, null: false, default: [])
      add(:issued_at, :utc_datetime_usec, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:revoked_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:credential_leases, [:credential_ref_id]))
    create(index(:credential_leases, [:connection_id]))
    create(index(:credential_leases, [:expires_at]))
  end
end
