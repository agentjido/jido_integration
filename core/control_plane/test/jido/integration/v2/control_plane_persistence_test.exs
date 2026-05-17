defmodule Jido.Integration.V2.ControlPlanePersistenceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.ControlPlane.Persistence
  alias Jido.Integration.V2.ControlPlane.RunLedger
  alias Jido.Integration.V2.ControlPlane.Stores

  @control_plane_store_keys [
    :run_store,
    :attempt_store,
    :event_store,
    :artifact_store,
    :claim_check_store,
    :target_store,
    :ingress_store,
    :profile_registry_store
  ]

  setup do
    previous_env = snapshot_env()

    Enum.each(@control_plane_store_keys, fn key ->
      Application.delete_env(:jido_integration_v2_control_plane, key)
    end)

    Persistence.reset!()

    on_exit(fn ->
      Persistence.reset!()
      restore_env(previous_env)
    end)

    :ok
  end

  test "defaults control-plane stores to mickey mouse memory without host config" do
    assert {:ok, resolution} = Persistence.resolve([])
    assert resolution.profile.id == :mickey_mouse
    assert resolution.profile.default_tier == :memory_ephemeral
    assert resolution.durable? == false
    assert resolution.store_modules.run_store == RunLedger
    assert Stores.run_store() == RunLedger
  end

  test "refuses durable control-plane selection without an explicit capability" do
    assert {:error, {:missing_store_capability, :postgres_shared}} =
             Persistence.resolve(profile: :integration_postgres)
  end

  test "records tenant resource connector partitions for run routing" do
    partition =
      Persistence.partition(
        tenant_ref: "tenant://tenant-1",
        resource_family: "linear",
        resource_instance_ref: "connector-instance://tenant-1/linear/a",
        data_class: :run_truth
      )

    assert partition.tenant_ref == "tenant://tenant-1"
    assert partition.resource_family == "linear"
    assert partition.resource_instance_ref == "connector-instance://tenant-1/linear/a"
    assert partition.data_class == :run_truth
  end

  defp snapshot_env do
    Map.new(@control_plane_store_keys, fn key ->
      {key, Application.fetch_env(:jido_integration_v2_control_plane, key)}
    end)
  end

  defp restore_env(previous_env) do
    Enum.each(previous_env, fn
      {key, {:ok, value}} -> Application.put_env(:jido_integration_v2_control_plane, key, value)
      {key, :error} -> Application.delete_env(:jido_integration_v2_control_plane, key)
    end)
  end
end
