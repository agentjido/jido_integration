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
