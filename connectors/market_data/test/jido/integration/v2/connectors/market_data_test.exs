defmodule Jido.Integration.V2.Connectors.MarketDataTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Connectors.MarketData
  alias Jido.Integration.V2.Connectors.MarketData.Conformance
  alias Jido.Integration.V2.Connectors.MarketData.Generated.Plugin, as: GeneratedPlugin

  test "publishes the stream action plus one common poll trigger proof on the shared consumer surface" do
    manifest = MarketData.manifest()
    capability_ids = Enum.map(manifest.capabilities, & &1.id)
    [trigger] = manifest.triggers

    assert manifest.connector == "market_data"
    assert manifest.runtime_families == [:direct, :stream]
    assert capability_ids == ["market.alert.detected", "market.ticks.pull"]

    capability = Enum.find(manifest.capabilities, &(&1.id == "market.ticks.pull"))
    trigger_capability = Enum.find(manifest.capabilities, &(&1.id == "market.alert.detected"))

    assert capability.runtime_class == :stream
    assert capability.id == "market.ticks.pull"
    assert trigger_capability.runtime_class == :direct
    assert trigger_capability.transport_profile == :poll

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

    assert trigger.consumer_surface == %{
             mode: :common,
             normalized_id: "market.alerts.detected",
             sensor_name: "market_alerts_detected"
           }

    assert trigger.jido.sensor == %{
             name: "market_alert_sensor",
             signal_type: "market.alert.detected",
             signal_source: "/ingress/poll/market_data/market.alert.detected"
           }

    assert Code.ensure_loaded?(
             Jido.Integration.V2.Connectors.MarketData.Generated.Actions.MarketTicksPull
           )

    assert Code.ensure_loaded?(
             Jido.Integration.V2.Connectors.MarketData.Generated.Sensors.MarketAlertsDetected
           )

    assert Code.ensure_loaded?(GeneratedPlugin)

    assert GeneratedPlugin.subscriptions() == [
             {Jido.Integration.V2.Connectors.MarketData.Generated.Sensors.MarketAlertsDetected,
              %{}}
           ]

    assert GeneratedPlugin.manifest().subscriptions == [
             {Jido.Integration.V2.Connectors.MarketData.Generated.Sensors.MarketAlertsDetected,
              %{}}
           ]
  end

  test "publishes matching ingress-definition evidence for the authored poll trigger" do
    assert [
             %{
               source: :poll,
               connector_id: "market_data",
               trigger_id: "market.alert.detected",
               capability_id: "market.alert.detected",
               signal_type: "market.alert.detected",
               signal_source: "/ingress/poll/market_data/market.alert.detected"
             }
           ] = MarketData.ingress_definitions()

    assert [
             %{
               capability_id: "market.alert.detected",
               signal_type: "market.alert.detected",
               signal_source: "/ingress/poll/market_data/market.alert.detected"
             }
           ] = Conformance.ingress_definitions()
  end
end
