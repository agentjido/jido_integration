defmodule Jido.Integration.GatewayTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Gateway
  alias Jido.Integration.Gateway.Policy
  alias Jido.Integration.Gateway.Policy.Default

  describe "Policy.compose/1" do
    test "returns :admit when all admit" do
      assert Policy.compose([:admit, :admit, :admit]) == :admit
    end

    test "returns :shed when any shed" do
      assert Policy.compose([:admit, :shed, :backoff]) == :shed
    end

    test "returns :backoff when any backoff but none shed" do
      assert Policy.compose([:admit, :backoff, :admit]) == :backoff
    end

    test "handles empty list" do
      assert Policy.compose([]) == :admit
    end
  end

  describe "Gateway.check/3" do
    test "default policy always admits" do
      assert Gateway.check(Default, %{}, %{}) == :admit
    end
  end

  describe "Gateway.check_chain/3" do
    test "chains multiple policies" do
      assert Gateway.check_chain([Default, Default], %{}, %{}) == :admit
    end
  end

  describe "Default policy" do
    test "partition_key returns :default" do
      assert Default.partition_key(%{}) == :default
    end

    test "capacity returns infinite tokens" do
      assert Default.capacity(:default) == {:tokens, :infinity}
    end
  end
end
