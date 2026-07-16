defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.CreateManagedProviderAccounts do
  use Ecto.Migration

  def change do
    create table(:managed_provider_accounts, primary_key: false) do
      add(:account_ref, :text, primary_key: true)
      add(:provider_family, :text, null: false)
      add(:tenant_id, :text, null: false)
      add(
        :connection_id,
        references(:connections, column: :connection_id, type: :text, on_delete: :nothing),
        null: false
      )
      add(:endpoint_ref, :text, null: false)
      add(:quota_scope_ref, :text, null: false)
      add(:generation, :integer, null: false)
      add(:fence, :bigint, null: false)
      add(:credential_handle_ref, :text, null: false)
      add(:secret_provider_ref, :text, null: false)
      add(:secret_binding_ref, :text, null: false)
      add(:state, :text, null: false)
      add(:revoked_at, :utc_datetime_usec)
      add(:revocation_ref, :text)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:managed_provider_accounts, [:connection_id]))
    create(index(:managed_provider_accounts, [:tenant_id, :provider_family, :state]))

    create table(:managed_credential_versions, primary_key: false) do
      add(
        :account_ref,
        references(:managed_provider_accounts,
          column: :account_ref,
          type: :text,
          on_delete: :delete_all
        ),
        null: false
      )
      add(:generation, :integer, null: false)
      add(:credential_handle_ref, :text, null: false)
      add(:secret_provider_ref, :text, null: false)
      add(:secret_binding_ref, :text, null: false)
      add(:supersedes_generation, :integer)
      add(:superseded_at, :utc_datetime_usec)
      add(:revoked_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:managed_credential_versions, [:account_ref, :generation],
             name: :managed_credential_versions_pkey
           ))
    create(index(:managed_credential_versions, [:account_ref, :revoked_at]))

    create(
      constraint(:managed_provider_accounts, :managed_provider_accounts_state_check,
        check: "state IN ('active', 'revoked')"
      )
    )

    create(
      constraint(:managed_provider_accounts, :managed_provider_accounts_generation_check,
        check: "generation > 0 AND fence >= 0"
      )
    )

    create(
      constraint(:managed_credential_versions, :managed_credential_versions_generation_check,
        check: "generation > 0"
      )
    )
  end
end
