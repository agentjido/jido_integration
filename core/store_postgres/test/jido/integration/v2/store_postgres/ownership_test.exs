defmodule Jido.Integration.V2.StorePostgres.OwnershipTest do
  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.TestSupport

  setup_all do
    TestSupport.setup_database!()
    Sandbox.mode(Repo, :auto)
    :ok
  end

  test "repo and migrations are owned by store_postgres" do
    assert Repo.config()[:otp_app] == :jido_integration_v2_store_postgres
    assert [Repo] = Application.get_env(:jido_integration_v2_store_postgres, :ecto_repos)
    assert File.dir?(StorePostgres.migrations_path())
  end

  test "migrations path follows the configured repo priv root" do
    otp_app = Repo.config()[:otp_app] || :jido_integration_v2_store_postgres
    repo_priv = Path.join(Repo.config()[:priv] || "priv/repo", "migrations")

    expected_path =
      case safe_app_dir(otp_app, repo_priv) do
        {:ok, path} ->
          path

        :error ->
          StorePostgres
          |> :code.which()
          |> to_string()
          |> Path.dirname()
          |> Path.join("../priv/repo/migrations")
          |> Path.expand()
      end

    assert StorePostgres.migrations_path() == expected_path
  end

  test "migrations path remains store_postgres-owned outside the package cwd" do
    expected_path = StorePostgres.migrations_path()
    foreign_cwd = Path.join(System.tmp_dir!(), "jido_integration_store_postgres_foreign_cwd")

    File.mkdir_p!(foreign_cwd)

    File.cd!(foreign_cwd, fn ->
      assert StorePostgres.migrations_path() == expected_path
    end)
  end

  test "default repo restarts preserve auto sandbox access for non-DataCase callers" do
    assert :ok = TestSupport.restart_repo!()
    assert %{rows: [[1]]} = Repo.query!("SELECT 1")
  end

  test "default claim-check root follows the effective test database name" do
    isolated_db_name = "jido_integration_v2_store_postgres_claim_check_isolation"

    assert TestSupport.default_claim_check_root(database: isolated_db_name) ==
             Path.join(
               System.tmp_dir!(),
               Path.join("jido_integration_v2_claim_check", isolated_db_name)
             )
  end

  defp safe_app_dir(otp_app, repo_priv) do
    {:ok, Application.app_dir(otp_app, repo_priv) |> Path.expand()}
  rescue
    ArgumentError -> :error
  end
end
