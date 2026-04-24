defmodule Platform.Cluster.RuntimeTest do
  use ExUnit.Case, async: false

  alias Platform.Cluster.Runtime

  defmodule EchoServer do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
    end

    @impl true
    def init(opts), do: {:ok, opts}
  end

  test "declares canonical Horde registry and dynamic supervisor child specs" do
    registry_name = Module.concat(__MODULE__, Registry)
    supervisor_name = Module.concat(__MODULE__, DynamicSupervisor)

    assert [
             {Horde.Registry, registry_opts},
             {Horde.DynamicSupervisor, supervisor_opts}
           ] =
             Runtime.child_specs(
               registry_name: registry_name,
               dynamic_supervisor_name: supervisor_name
             )

    assert Keyword.fetch!(registry_opts, :name) == registry_name
    assert Keyword.fetch!(registry_opts, :keys) == :unique
    assert Keyword.fetch!(registry_opts, :members) == :auto
    assert Keyword.fetch!(registry_opts, :delta_crdt_options) == [sync_interval: 50]

    assert Keyword.fetch!(supervisor_opts, :name) == supervisor_name
    assert Keyword.fetch!(supervisor_opts, :strategy) == :one_for_one
    assert Keyword.fetch!(supervisor_opts, :members) == :auto

    assert Keyword.fetch!(supervisor_opts, :distribution_strategy) ==
             Horde.UniformQuorumDistribution

    assert Keyword.fetch!(supervisor_opts, :delta_crdt_options) == [sync_interval: 50]
  end

  test "documents the node-role tags used by memory-path nodes" do
    assert Runtime.node_roles() == [
             :web,
             :worker,
             :temporal_worker,
             :memory_reader,
             :memory_writer,
             :stacklab_probe
           ]
  end

  test "registers and locates singleton processes through the canonical runtime API" do
    start_supervised!(Runtime.child_spec([]))

    assert {:ok, pid} =
             Runtime.register_singleton(:memory_reader, "tenant://alpha", {EchoServer, []})

    assert {:ok, ^pid} = Runtime.locate(:memory_reader, "tenant://alpha")

    assert {:ok, ^pid} =
             Runtime.register_singleton(:memory_reader, "tenant://alpha", {EchoServer, []})
  end

  test "keeps memory-path singleton source free of Erlang global registration" do
    source =
      File.read!(
        Path.expand(
          "../../../lib/platform/cluster/runtime.ex",
          __DIR__
        )
      )

    refute source =~ ":global"
    assert Code.ensure_loaded?(Runtime)
    assert function_exported?(Runtime, :register_singleton, 3)
    assert function_exported?(Runtime, :locate, 2)
  end
end
