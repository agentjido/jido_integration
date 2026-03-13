defmodule Jido.Integration.V2.StoreLocal.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Jido.Integration.V2.StoreLocal.TestSupport

  using do
    quote do
      import Jido.Integration.V2.StoreLocal.Case
      import Jido.Integration.V2.StoreLocal.Fixtures

      alias Jido.Integration.V2.StoreLocal.TestSupport
    end
  end

  setup do
    storage_dir = TestSupport.tmp_dir!()
    :ok = TestSupport.reconfigure!(storage_dir: storage_dir)
    :ok = TestSupport.reset_all!()

    on_exit(fn ->
      TestSupport.cleanup!(storage_dir)
    end)

    %{storage_dir: storage_dir}
  end

  @spec fetch_map_value(map(), atom()) :: term()
  def fetch_map_value(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
