defmodule Jido.Integration.V2.StorePostgres do
  @moduledoc """
  Postgres durability package owning the Repo, migrations, and SQL sandbox posture.
  """

  alias GroundPlane.PersistencePolicy
  alias Jido.Integration.V2.StorePostgres.Repo

  @spec repo() :: module()
  def repo, do: Repo

  @spec store_capability() :: {:ok, PersistencePolicy.StoreCapability.t()} | {:error, term()}
  def store_capability do
    PersistencePolicy.StoreCapability.new(
      store_ref: :jido_integration_store_postgres,
      tier: :postgres_shared,
      data_classes: [:auth_truth, :control_plane_truth, :submission_ledger],
      adapter: :jido_integration_store_postgres,
      restart_safe?: true,
      partitions: [
        %PersistencePolicy.Partition{
          data_class: :jido_integration,
          retention_class: :shared_postgres
        }
      ]
    )
  end

  @spec preflight(keyword() | map()) :: :ok | {:error, term()}
  def preflight(opts \\ []) do
    attrs = Map.new(opts)
    profile_hint = Map.get(attrs, :profile) || Map.get(attrs, "profile") || :integration_postgres

    capabilities =
      if Map.has_key?(attrs, :capabilities) or Map.has_key?(attrs, "capabilities") do
        List.wrap(Map.get(attrs, :capabilities) || Map.get(attrs, "capabilities"))
      else
        {:ok, capability} = store_capability()
        [capability]
      end

    with {:ok, profile} <- PersistencePolicy.resolve(profile: profile_hint) do
      PersistencePolicy.preflight(profile, capabilities, fn _capability -> :ok end)
    end
  end

  @spec auth_store_modules() :: map()
  def auth_store_modules do
    %{
      credential_store: Jido.Integration.V2.StorePostgres.CredentialStore,
      lease_store: Jido.Integration.V2.StorePostgres.LeaseStore,
      connection_store: Jido.Integration.V2.StorePostgres.ConnectionStore,
      install_store: Jido.Integration.V2.StorePostgres.InstallStore
    }
  end

  @spec control_plane_store_modules() :: map()
  def control_plane_store_modules do
    %{
      run_store: Jido.Integration.V2.StorePostgres.RunStore,
      attempt_store: Jido.Integration.V2.StorePostgres.AttemptStore,
      event_store: Jido.Integration.V2.StorePostgres.EventStore,
      artifact_store: Jido.Integration.V2.StorePostgres.ArtifactStore,
      claim_check_store: Jido.Integration.V2.StorePostgres.ClaimCheckStore,
      target_store: Jido.Integration.V2.StorePostgres.TargetStore,
      ingress_store: Jido.Integration.V2.StorePostgres.IngressStore,
      profile_registry_store: Jido.Integration.V2.StorePostgres.ProfileRegistryStore
    }
  end

  @spec assert_started!() :: :ok
  def assert_started! do
    if Process.whereis(Repo) do
      :ok
    else
      raise ArgumentError,
            "store_postgres repo is not started; start Jido.Integration.V2.StorePostgres.Application before using Jido.Integration.V2.StorePostgres"
    end
  end

  @spec migrations_path() :: String.t()
  def migrations_path do
    otp_app = Repo.config()[:otp_app] || :jido_integration_v2_store_postgres

    repo_priv =
      Repo.config()
      |> Keyword.get(:priv, "priv/repo")
      |> Path.join("migrations")

    case safe_app_dir(otp_app, repo_priv) do
      {:ok, path} ->
        path

      :error ->
        repo_priv
        |> app_root_from_code_path(__MODULE__)
        |> Path.expand()
    end
  end

  defp safe_app_dir(otp_app, repo_priv) do
    {:ok, Application.app_dir(otp_app, repo_priv) |> Path.expand()}
  rescue
    ArgumentError -> :error
  end

  defp app_root_from_code_path(repo_priv, module) do
    module
    |> :code.which()
    |> to_string()
    |> Path.dirname()
    |> Path.join("..")
    |> Path.expand()
    |> Path.join(repo_priv)
  end
end
