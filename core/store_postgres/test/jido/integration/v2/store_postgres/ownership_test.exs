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
    expected_path =
      Repo.config()
      |> Keyword.get(:priv, "priv/repo")
      |> Path.join("migrations")
      |> Path.expand()

    assert StorePostgres.migrations_path() == expected_path
  end

  test "default repo restarts preserve auto sandbox access for non-DataCase callers" do
    assert :ok = TestSupport.restart_repo!()
    assert %{rows: [[1]]} = Repo.query!("SELECT 1")
  end
end
