defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.CreateSimulationProfileRegistryEntries do
  use Ecto.Migration

  def change do
    create table(:simulation_profile_registry_entries, primary_key: false) do
      add(:profile_id, :text, primary_key: true)
      add(:contract_version, :text, null: false)
      add(:profile_version, :text, null: false)
      add(:owner_refs, {:array, :text}, null: false, default: [])
      add(:environment_scope, :text, null: false)
      add(:lower_scenario_refs, {:array, :text}, null: false, default: [])
      add(:no_egress_policy_ref, :text, null: false)
      add(:audit_install_actor_ref, :text, null: false)
      add(:audit_install_timestamp, :utc_datetime_usec, null: false)
      add(:audit_update_history_refs, {:array, :text}, null: false, default: [])
      add(:audit_remove_actor_ref_or_null, :text)
      add(:cleanup_status, :text, null: false)
      add(:cleanup_artifact_refs, {:array, :text}, null: false, default: [])
      add(:owner_evidence_refs, {:array, :text}, null: false, default: [])

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:simulation_profile_registry_entries, [:environment_scope]))
    create(index(:simulation_profile_registry_entries, [:cleanup_status]))
  end
end
