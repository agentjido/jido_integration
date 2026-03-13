defmodule Jido.Integration.V2.Connectors.MarketDataTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Connectors.MarketData
  alias Jido.Integration.V2.Manifest

  test "publishes a stream manifest" do
    assert %Manifest{connector: "market_data", capabilities: [capability]} = MarketData.manifest()
    assert capability.runtime_class == :stream
    assert capability.id == "market.ticks.pull"
    assert capability.metadata.required_scopes == ["market:read"]
    assert capability.metadata.policy.environment.allowed == [:prod]
    assert capability.metadata.policy.sandbox.egress == :blocked
    assert capability.metadata.policy.sandbox.allowed_tools == ["market.feed.pull"]
  end
end
