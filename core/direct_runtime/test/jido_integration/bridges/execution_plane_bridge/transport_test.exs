defmodule JidoIntegration.Bridges.ExecutionPlaneBridge.TransportTest do
  use ExUnit.Case, async: true

  alias JidoIntegration.Bridges.ExecutionPlaneBridge.Transport

  defmodule DirectTarget do
    def execute_lane(request, opts) do
      {:ok, %{"mode" => "direct", "request" => request, "timeout" => opts[:timeout]}}
    end
  end

  test "direct transport calls an explicitly supplied Execution Plane facade" do
    assert {:ok, result} =
             Transport.Direct.execute_lane(%{"lane" => "diagnostic"},
               target: DirectTarget,
               timeout: 50
             )

    assert result["mode"] == "direct"
    assert result["timeout"] == 50
  end

  test "distributed transport calls an explicitly supplied Execution Plane facade" do
    assert {:ok, result} =
             Transport.Distributed.execute_lane(%{"lane" => "diagnostic"},
               node: Node.self(),
               facade_module: DirectTarget,
               timeout: 1_000
             )

    assert result["mode"] == "direct"
  end

  test "fixture transport provides deterministic lower-lane evidence" do
    assert {:ok, result} = Transport.Fixture.execute_lane(%{}, [])
    assert result["lower_receipt_ref"] == "lower://fixture/execution-plane"
  end

  test "runtime deps select an Execution Plane transport explicitly" do
    assert {:ok, deps} =
             Transport.RuntimeDeps.new(
               transport: Transport.Fixture,
               transport_opts: [execute_lane: {:ok, %{"status" => "completed"}}]
             )

    assert {:ok, %{"status" => "completed"}} = Transport.RuntimeDeps.execute_lane(deps, %{})
  end
end
