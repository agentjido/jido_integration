defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.AddLeaseRedemptionTruth do
  use Ecto.Migration

  def change do
    alter table(:credential_leases) do
      add(:redemption_count, :integer, null: false, default: 0)
      add(:last_redeemed_at, :utc_datetime_usec)
      add(:last_materialization_ref, :text)
    end

    create(index(:credential_leases, [:tenant_id, :last_redeemed_at]))
  end
end
