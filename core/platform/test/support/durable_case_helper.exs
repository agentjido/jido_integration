defmodule Jido.Integration.V2.Platform.DurableSupport do
  @moduledoc false

  alias Ecto.Adapters.SQL.Sandbox
  alias Jido.Integration.V2.RuntimeRouter
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.TestSupport

  @control_plane_keys [
    :run_store,
    :attempt_store,
    :event_store,
    :artifact_store,
    :claim_check_store,
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
  @brain_ingress_keys [:submission_ledger]
  @store_postgres_keys [:ecto_repos, Repo, :claim_check_root]

  @spec setup_all!(keyword()) :: :ok
  def setup_all!(opts \\ []) do
    TestSupport.setup_database!(opts)
    maybe_enable_auto_sandbox(opts)
    :ok
  end

  @spec setup!(keyword()) :: (-> :ok)
  def setup!(opts \\ []) do
    previous_env = snapshot_env()
    RuntimeRouter.start!()
    TestSupport.configure_defaults!(opts)
    maybe_enable_auto_sandbox(opts)

    fn ->
      restore_env(previous_env)
      :ok
    end
  end

  defp maybe_enable_auto_sandbox(opts) do
    if TestSupport.repo_config(opts)[:pool] == Sandbox do
      Sandbox.mode(Repo, :auto)
    end
  end

  defp snapshot_env do
    %{
      control_plane: snapshot_keys(:jido_integration_v2_control_plane, @control_plane_keys),
      auth: snapshot_keys(:jido_integration_v2_auth, @auth_keys),
      brain_ingress: snapshot_keys(:jido_integration_v2_brain_ingress, @brain_ingress_keys),
      store_postgres: snapshot_keys(:jido_integration_v2_store_postgres, @store_postgres_keys)
    }
  end

  defp restore_env(previous_env) do
    restore_keys(:jido_integration_v2_control_plane, previous_env.control_plane)
    restore_keys(:jido_integration_v2_auth, previous_env.auth)
    restore_keys(:jido_integration_v2_brain_ingress, previous_env.brain_ingress)
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

defmodule Jido.Integration.V2.Platform.DurableCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Jido.Integration.V2.Platform.DurableSupport

  using do
    quote do
      use ExUnit.Case, async: false
    end
  end

  setup_all do
    DurableSupport.setup_all!()
    :ok
  end

  setup do
    cleanup = DurableSupport.setup!()
    on_exit(cleanup)
    :ok
  end
end
