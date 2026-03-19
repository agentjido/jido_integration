defmodule Jido.Integration.V2.Connectors.MarketData do
  @moduledoc """
  Example stream connector package.

  It preserves the legacy `integration_stream_bridge` proof path as a migration
  shim while the control plane consolidates on real Harness-backed runtime
  families.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Connectors.MarketData.Provider
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "market_data",
      auth:
        AuthSpec.new!(%{
          binding_kind: :connection_id,
          auth_type: :api_token,
          install: %{required: true},
          reauth: %{supported: false},
          requested_scopes: ["market:read"],
          lease_fields: ["access_token"],
          secret_names: []
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "Market Data",
          description: "Example stream connector package for feed-style capabilities",
          category: "market_data",
          tags: ["stream", "quotes"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        }),
      operations: [
        OperationSpec.new!(%{
          operation_id: "market.ticks.pull",
          name: "ticks_pull",
          display_name: "Pull ticks",
          description: "Pulls a market data feed batch",
          runtime_class: :stream,
          transport_mode: :market_feed,
          handler: Provider,
          input_schema: Zoi.map(description: "Feed input"),
          output_schema: Zoi.map(description: "Feed output"),
          permissions: %{required_scopes: ["market:read"]},
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
          },
          upstream: %{protocol: :market_feed},
          jido: %{action: %{name: "market_ticks_pull"}}
        })
      ],
      triggers: [],
      runtime_families: [:stream]
    })
  end
end
