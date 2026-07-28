defmodule JidoIntegration.Bridges.ExecutionPlaneBridge.TransportTest do
  use ExUnit.Case, async: true

  alias JidoIntegration.Bridges.ExecutionPlaneBridge.Transport

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
