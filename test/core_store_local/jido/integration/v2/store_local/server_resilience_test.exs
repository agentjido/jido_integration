defmodule Jido.Integration.V2.StoreLocal.ServerResilienceTest do
  use Jido.Integration.V2.StoreLocal.Case

  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.Application, as: StoreLocalApplication
  alias Jido.Integration.V2.StoreLocal.Server
  alias Jido.Integration.V2.StoreLocal.State

  test "startup recovers from an unsafe persisted state file" do
    path = StoreLocal.storage_path()

    assert :ok == Supervisor.terminate_child(StoreLocalApplication, Server)
    File.write!(path, <<131, 80, 0, 0, 0, 0>>)

    assert {:ok, _pid} = Supervisor.restart_child(StoreLocalApplication, Server)
    assert Server.snapshot() == State.new()
    assert :erlang.binary_to_term(File.read!(path), [:safe]) == State.new()
  end
end
