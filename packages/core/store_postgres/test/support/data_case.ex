defmodule Jido.Integration.V2.StorePostgres.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Jido.Integration.V2.StorePostgres.TestSupport

  using do
    quote do
      alias Jido.Integration.V2.StorePostgres.Repo
      import Ecto.Query
      import Jido.Integration.V2.StorePostgres.DataCase
      import Jido.Integration.V2.StorePostgres.Fixtures
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Jido.Integration.V2.StorePostgres.Repo)

    unless tags[:async] do
      Sandbox.mode(Jido.Integration.V2.StorePostgres.Repo, {:shared, self()})
    end

    :ok
  end

  @spec restart_repo!(atom()) :: :ok
  def restart_repo!(mode \\ :manual), do: TestSupport.restart_repo!(mode)

  @spec fetch_map_value(map(), atom()) :: term()
  def fetch_map_value(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
