defmodule Jido.Integration.V2.StorePostgres.ProfileRegistryStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.ProfileRegistryStore

  import Ecto.Query

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ServiceSimulationProfile
  alias Jido.Integration.V2.SimulationProfileRegistryEntry
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.ProfileRegistryEntryRecord

  @impl true
  def install_profile(profile, installed_scenarios, attrs) do
    case SimulationProfileRegistryEntry.install(profile, installed_scenarios, attrs) do
      {:ok, entry} ->
        entry
        |> install_entry()
        |> unwrap_transaction()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def update_profile(profile, installed_scenarios, attrs) do
    case profile_id_from(profile) do
      nil ->
        {:error, :unknown_profile}

      profile_id ->
        profile_id
        |> update_entry(profile, installed_scenarios, attrs)
        |> unwrap_transaction()
    end
  end

  @impl true
  def remove_profile(profile_id, attrs) do
    profile_id
    |> remove_profile_entry(attrs)
    |> unwrap_transaction()
  end

  @impl true
  def fetch_profile(profile_id) do
    case Repo.get(ProfileRegistryEntryRecord, profile_id) do
      nil -> :error
      record -> {:ok, to_contract(record)}
    end
  end

  @impl true
  def select_profile(profile_id, environment_scope, owner_ref) do
    with {:ok, entry} <- fetch_profile(profile_id) do
      SimulationProfileRegistryEntry.select(entry, environment_scope, owner_ref)
    end
  end

  @impl true
  def list_profiles(filters \\ %{}) do
    from(entry in ProfileRegistryEntryRecord,
      order_by: [asc: entry.audit_install_timestamp, asc: entry.profile_id]
    )
    |> Repo.all()
    |> Enum.map(&to_contract/1)
    |> filter_records(filters)
  end

  def reset! do
    StorePostgres.assert_started!()
    Repo.delete_all(ProfileRegistryEntryRecord)
    :ok
  end

  defp install_entry(%SimulationProfileRegistryEntry{} = entry) do
    Repo.transaction(fn ->
      entry.profile_id
      |> fetch_record()
      |> persist_installed_entry(entry)
    end)
  end

  defp update_entry(profile_id, profile, installed_scenarios, attrs) do
    Repo.transaction(fn ->
      profile_id
      |> fetch_record()
      |> persist_updated_entry(profile, installed_scenarios, attrs)
    end)
  end

  defp remove_profile_entry(profile_id, attrs) do
    Repo.transaction(fn ->
      profile_id
      |> fetch_record()
      |> persist_removed_entry(attrs)
    end)
  end

  defp fetch_record(profile_id), do: Repo.get(ProfileRegistryEntryRecord, profile_id)

  defp persist_installed_entry(nil, entry), do: insert_entry(entry)

  defp persist_installed_entry(%ProfileRegistryEntryRecord{} = record, entry) do
    existing = to_contract(record)

    case existing.profile_version == entry.profile_version do
      true -> {:ok, existing}
      false -> {:error, :concurrent_install_same_id_different_version}
    end
  end

  defp persist_updated_entry(nil, _profile, _installed_scenarios, _attrs) do
    {:error, :unknown_profile}
  end

  defp persist_updated_entry(%ProfileRegistryEntryRecord{} = record, profile, scenarios, attrs) do
    record
    |> to_contract()
    |> SimulationProfileRegistryEntry.update(profile, scenarios, attrs)
    |> update_record_after_contract(record)
  end

  defp update_record_after_contract({:ok, updated}, record), do: update_record(record, updated)
  defp update_record_after_contract({:error, reason}, _record), do: {:error, reason}

  defp persist_removed_entry(nil, _attrs), do: {:error, :unknown_profile}

  defp persist_removed_entry(%ProfileRegistryEntryRecord{} = record, attrs) do
    record
    |> to_contract()
    |> remove_entry(attrs)
    |> update_record_after_remove(record)
  end

  defp update_record_after_remove({:ok, removed, reply}, record) do
    case update_record(record, removed) do
      {:ok, _persisted} -> reply
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_record_after_remove({:error, reason}, _record), do: {:error, reason}

  defp insert_entry(%SimulationProfileRegistryEntry{} = entry) do
    %ProfileRegistryEntryRecord{}
    |> ProfileRegistryEntryRecord.changeset(to_record_attrs(entry))
    |> Repo.insert()
    |> case do
      {:ok, record} -> {:ok, to_contract(record)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp update_record(
         %ProfileRegistryEntryRecord{} = record,
         %SimulationProfileRegistryEntry{} = entry
       ) do
    record
    |> ProfileRegistryEntryRecord.changeset(to_record_attrs(entry))
    |> Repo.update()
    |> case do
      {:ok, record} -> {:ok, to_contract(record)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp to_record_attrs(%SimulationProfileRegistryEntry{} = entry) do
    %{
      profile_id: entry.profile_id,
      contract_version: entry.contract_version,
      profile_version: entry.profile_version,
      owner_refs: entry.owner_refs,
      environment_scope: entry.environment_scope,
      lower_scenario_refs: entry.lower_scenario_refs,
      no_egress_policy_ref: entry.no_egress_policy_ref,
      audit_install_actor_ref: entry.audit_install_actor_ref,
      audit_install_timestamp: entry.audit_install_timestamp,
      audit_update_history_refs: entry.audit_update_history_refs,
      audit_remove_actor_ref_or_null: entry.audit_remove_actor_ref_or_null,
      cleanup_status: entry.cleanup_status,
      cleanup_artifact_refs: entry.cleanup_artifact_refs,
      owner_evidence_refs: entry.owner_evidence_refs
    }
  end

  defp to_contract(%ProfileRegistryEntryRecord{} = record) do
    SimulationProfileRegistryEntry.new!(%{
      profile_id: record.profile_id,
      contract_version: record.contract_version,
      profile_version: record.profile_version,
      owner_refs: record.owner_refs || [],
      environment_scope: record.environment_scope,
      lower_scenario_refs: record.lower_scenario_refs || [],
      no_egress_policy_ref: record.no_egress_policy_ref,
      audit_install_actor_ref: record.audit_install_actor_ref,
      audit_install_timestamp: record.audit_install_timestamp,
      audit_update_history_refs: record.audit_update_history_refs || [],
      audit_remove_actor_ref_or_null: record.audit_remove_actor_ref_or_null,
      cleanup_status: record.cleanup_status,
      cleanup_artifact_refs: record.cleanup_artifact_refs || [],
      owner_evidence_refs: record.owner_evidence_refs || []
    })
  end

  defp remove_entry(%SimulationProfileRegistryEntry{} = current, attrs) do
    removed = SimulationProfileRegistryEntry.remove!(current, attrs)

    reply =
      case removed.cleanup_status do
        :cleanup_failed -> {:error, :cleanup_failure}
        :removed -> {:ok, removed}
      end

    {:ok, removed, reply}
  rescue
    error in ArgumentError ->
      {:error, registry_failure_reason(error)}
  end

  defp unwrap_transaction({:ok, result}), do: result
  defp unwrap_transaction({:error, reason}), do: {:error, reason}

  defp profile_id_from(%ServiceSimulationProfile{} = profile), do: profile.profile_id

  defp profile_id_from(profile) when is_map(profile) or is_list(profile) do
    profile
    |> Map.new()
    |> Contracts.get(:profile_id)
  end

  defp profile_id_from(_profile), do: nil

  defp filter_records(records, filters) when is_map(filters) do
    Enum.filter(records, fn record ->
      Enum.all?(filters, fn {key, value} -> Map.get(record, key) == value end)
    end)
  end

  defp registry_failure_reason(%ArgumentError{message: message}) do
    if String.contains?(message, "cleanup"), do: :cleanup_failure, else: :invalid_registry_entry
  end
end
