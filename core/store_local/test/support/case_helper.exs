defmodule Jido.Integration.V2.StoreLocal.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Jido.Integration.V2.StoreLocal.TestSupport

  using do
    quote do
      import Jido.Integration.V2.StoreLocal.Case
      import Jido.Integration.V2.StoreLocal.Fixtures

      alias Jido.Integration.V2.StoreLocal.TestSupport
    end
  end

  setup do
    previous_env = snapshot_env()
    storage_dir = TestSupport.tmp_dir!()
    :ok = TestSupport.reconfigure!(storage_dir: storage_dir)
    :ok = TestSupport.reset_all!()

    on_exit(fn ->
      restore_env(previous_env)
      TestSupport.cleanup!(storage_dir)
    end)

    %{storage_dir: storage_dir}
  end

  @spec fetch_map_value(map(), atom()) :: term()
  def fetch_map_value(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp snapshot_env do
    %{
      auth:
        snapshot_keys(:jido_integration_v2_auth, [
          :credential_store,
          :lease_store,
          :connection_store,
          :install_store
        ]),
      control_plane:
        snapshot_keys(:jido_integration_v2_control_plane, [
          :run_store,
          :attempt_store,
          :event_store,
          :artifact_store,
          :target_store,
          :ingress_store
        ]),
      store_local: snapshot_keys(:jido_integration_v2_store_local, [:storage_dir])
    }
  end

  defp restore_env(previous_env) do
    restore_keys(:jido_integration_v2_auth, previous_env.auth)
    restore_keys(:jido_integration_v2_control_plane, previous_env.control_plane)
    restore_keys(:jido_integration_v2_store_local, previous_env.store_local)
  end

  defp snapshot_keys(app, keys) do
    Map.new(keys, fn key ->
      {key, Application.fetch_env(app, key)}
    end)
  end

  defp restore_keys(app, env_map) do
    Enum.each(env_map, fn
      {key, {:ok, value}} -> Application.put_env(app, key, value)
      {key, :error} -> Application.delete_env(app, key)
    end)
  end
end
