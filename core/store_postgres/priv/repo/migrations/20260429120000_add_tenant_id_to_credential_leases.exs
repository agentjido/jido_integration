defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.AddTenantIdToCredentialLeases do
  use Ecto.Migration

  def change do
    alter table(:credential_leases) do
      add(:tenant_id, :text)
    end

    execute("""
    UPDATE credential_leases AS leases
    SET tenant_id = connections.tenant_id
    FROM connections
    WHERE leases.connection_id = connections.connection_id
      AND leases.tenant_id IS NULL
    """)

    execute("""
    UPDATE credential_leases
    SET tenant_id = metadata->>'tenant_id'
    WHERE tenant_id IS NULL
      AND metadata ? 'tenant_id'
    """)

    execute("""
    ALTER TABLE credential_leases
      ALTER COLUMN tenant_id SET NOT NULL
    """)

    create(index(:credential_leases, [:tenant_id, :credential_ref_id]))
    create(index(:credential_leases, [:tenant_id, :connection_id]))
  end
end
