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
    Repo.config()
    |> Keyword.get(:priv, "priv/repo")
    |> Path.join("migrations")
    |> Path.expand()
  end
end
