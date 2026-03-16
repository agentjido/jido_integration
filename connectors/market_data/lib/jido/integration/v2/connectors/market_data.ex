defmodule Jido.Integration.V2.Connectors.MarketData do
  @moduledoc """
  Example stream connector package.

  It preserves the legacy `integration_stream_bridge` proof path as a migration
  shim while the control plane consolidates on real Harness-backed runtime
  families.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Connectors.MarketData.Provider
  alias Jido.Integration.V2.Manifest

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "market_data",
      capabilities: [
        Capability.new!(%{
          id: "market.ticks.pull",
          connector: "market_data",
          runtime_class: :stream,
          kind: :stream_read,
          transport_profile: :market_feed,
          handler: Provider,
          metadata: %{
            required_scopes: ["market:read"],
            runtime: %{
              driver: "integration_stream_bridge"
            },
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :blocked,
                approvals: :auto,
                allowed_tools: ["market.feed.pull"]
              }
            }
          }
        })
      ]
    })
  end
end
