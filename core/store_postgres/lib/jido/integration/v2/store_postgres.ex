defmodule Jido.Integration.V2.StorePostgres do
  @moduledoc """
  Postgres durability package owning the Repo, migrations, and SQL sandbox posture.
  """

  alias Jido.Integration.V2.StorePostgres.Repo

  @spec repo() :: module()
  def repo, do: Repo

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
    repo_priv =
      Repo.config()
      |> Keyword.get(:priv, "priv/repo")
      |> Path.join("migrations")

    Application.app_dir(:jido_integration_v2_store_postgres, repo_priv)
    |> Path.expand()
  end
end
