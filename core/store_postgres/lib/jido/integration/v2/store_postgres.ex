defmodule Jido.Integration.V2.StorePostgres do
  @moduledoc """
  Postgres durability package owning the Repo, migrations, and SQL sandbox posture.
  """

  alias Jido.Integration.V2.StorePostgres.Repo

  @spec repo() :: module()
  def repo, do: Repo

  @spec migrations_path() :: String.t()
  def migrations_path do
    Application.app_dir(:jido_integration_v2_store_postgres, "priv/repo/migrations")
  end
end
