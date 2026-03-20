defmodule Jido.Integration.V2.Connectors.MarketDataTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Connectors.MarketData

  test "publishes a stream manifest on the shared asm-backed common surface" do
    manifest = MarketData.manifest()
    [capability] = manifest.capabilities

    assert manifest.connector == "market_data"
    assert capability.runtime_class == :stream
    assert capability.id == "market.ticks.pull"

    assert capability.metadata.runtime == %{
             driver: "asm",
             provider: :claude,
             options: %{}
           }

    assert capability.metadata.consumer_surface == %{
             mode: :common,
             normalized_id: "market.ticks.pull",
             action_name: "market_ticks_pull"
           }

    assert capability.metadata.runtime_family == %{
             session_affinity: :target,
             resumable: false,
             approval_required: false,
             stream_capable: true,
             lifecycle_owner: :asm,
             runtime_ref: :session
           }

    assert capability.metadata.required_scopes == ["market:read"]
    assert capability.metadata.policy.environment.allowed == [:prod]
    assert capability.metadata.policy.sandbox.egress == :blocked
    assert capability.metadata.policy.sandbox.allowed_tools == ["market.feed.pull"]

    assert Code.ensure_loaded?(
             Jido.Integration.V2.Connectors.MarketData.Generated.Actions.MarketTicksPull
           )

    assert Code.ensure_loaded?(Jido.Integration.V2.Connectors.MarketData.Generated.Plugin)
  end
end
