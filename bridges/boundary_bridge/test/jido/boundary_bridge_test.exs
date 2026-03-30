defmodule Jido.BoundaryBridgeTest do
  use ExUnit.Case
  doctest Jido.BoundaryBridge

  test "exposes the package role" do
    assert Jido.BoundaryBridge.role() == :lower_boundary_bridge
  end
end
