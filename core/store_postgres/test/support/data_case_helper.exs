defmodule Jido.Integration.V2.StorePostgres.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.TestSupport

  @control_plane_keys [
    :run_store,
    :attempt_store,
    :event_store,
    :artifact_store,
    :target_store,
    :ingress_store
  ]
  @auth_keys [
    :credential_store,
    :lease_store,
    :connection_store,
    :install_store,
    :keyring,
    :refresh_handler,
    :external_secret_resolver
  ]
  @store_postgres_keys [:ecto_repos, Repo]

  using do
    quote do
      alias Jido.Integration.V2.StorePostgres.Repo
      import Ecto.Query
      import Jido.Integration.V2.StorePostgres.DataCase
      import Jido.Integration.V2.StorePostgres.Fixtures
    end
  end

  setup_all do
    TestSupport.setup_database!()
    :ok
  end

  setup tags do
    previous_env = snapshot_env()
    TestSupport.configure_defaults!()
    :ok = Sandbox.checkout(Repo)

    unless tags[:async] do
      Sandbox.mode(Repo, {:shared, self()})
    end

    TestSupport.reset_database!()

    on_exit(fn ->
      restore_env(previous_env)
    end)

    :ok
  end

  @spec restart_repo!(atom()) :: :ok
  def restart_repo!(mode \\ :auto), do: TestSupport.restart_repo!(mode)

  @spec fetch_map_value(map(), atom()) :: term()
  def fetch_map_value(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp snapshot_env do
    %{
      control_plane: snapshot_keys(:jido_integration_v2_control_plane, @control_plane_keys),
      auth: snapshot_keys(:jido_integration_v2_auth, @auth_keys),
      store_postgres: snapshot_keys(:jido_integration_v2_store_postgres, @store_postgres_keys)
    }
  end

  defp restore_env(previous_env) do
    restore_keys(:jido_integration_v2_control_plane, previous_env.control_plane)
    restore_keys(:jido_integration_v2_auth, previous_env.auth)
    restore_keys(:jido_integration_v2_store_postgres, previous_env.store_postgres)
    :ok
  end

  defp snapshot_keys(app, keys) do
    Map.new(keys, fn key -> {key, Application.get_env(app, key, :__missing__)} end)
  end

  defp restore_keys(app, snapshot) do
    Enum.each(snapshot, fn
      {key, :__missing__} -> Application.delete_env(app, key)
      {key, value} -> Application.put_env(app, key, value)
    end)
  end
end
