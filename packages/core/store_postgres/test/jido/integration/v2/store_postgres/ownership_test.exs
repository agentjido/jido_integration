defmodule Jido.Integration.V2.StorePostgres.OwnershipTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo

  test "repo and migrations are owned by store_postgres" do
    assert Repo.config()[:otp_app] == :jido_integration_v2_store_postgres
    assert [Repo] = Application.get_env(:jido_integration_v2_store_postgres, :ecto_repos)
    assert File.dir?(StorePostgres.migrations_path())
  end

  test "owner packages do not own foundation migrations" do
    refute File.dir?(
             Application.app_dir(:jido_integration_v2_control_plane, "priv/repo/migrations")
           )

    refute File.dir?(Application.app_dir(:jido_integration_v2_auth, "priv/repo/migrations"))
  end
end
