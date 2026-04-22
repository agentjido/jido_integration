defmodule Jido.Integration.V2.StorePostgres.Schemas.ProfileRegistryEntryRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Jido.Integration.V2.SimulationProfileRegistryEntry

  @primary_key {:profile_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "simulation_profile_registry_entries" do
    field(:contract_version, :string)
    field(:profile_version, :string)
    field(:owner_refs, {:array, :string}, default: [])
    field(:environment_scope, :string)
    field(:lower_scenario_refs, {:array, :string}, default: [])
    field(:no_egress_policy_ref, :string)
    field(:audit_install_actor_ref, :string)
    field(:audit_install_timestamp, :utc_datetime_usec)
    field(:audit_update_history_refs, {:array, :string}, default: [])
    field(:audit_remove_actor_ref_or_null, :string)
    field(:cleanup_status, Ecto.Enum, values: SimulationProfileRegistryEntry.cleanup_statuses())
    field(:cleanup_artifact_refs, {:array, :string}, default: [])
    field(:owner_evidence_refs, {:array, :string}, default: [])

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :profile_id,
      :contract_version,
      :profile_version,
      :owner_refs,
      :environment_scope,
      :lower_scenario_refs,
      :no_egress_policy_ref,
      :audit_install_actor_ref,
      :audit_install_timestamp,
      :audit_update_history_refs,
      :audit_remove_actor_ref_or_null,
      :cleanup_status,
      :cleanup_artifact_refs,
      :owner_evidence_refs,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :profile_id,
      :contract_version,
      :profile_version,
      :owner_refs,
      :environment_scope,
      :lower_scenario_refs,
      :no_egress_policy_ref,
      :audit_install_actor_ref,
      :audit_install_timestamp,
      :audit_update_history_refs,
      :cleanup_status,
      :cleanup_artifact_refs,
      :owner_evidence_refs
    ])
  end
end
