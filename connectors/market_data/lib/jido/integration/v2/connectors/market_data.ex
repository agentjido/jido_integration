defmodule Jido.Integration.V2.Connectors.MarketData do
  @moduledoc """
  Example stream connector package.

  This connector publishes the canonical stream-family authored shape on the
  shared common consumer-surface spine through the `Jido.Harness` `asm`
  driver.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Connectors.MarketData.AlertTriggerHandler
  alias Jido.Integration.V2.Connectors.MarketData.Handler
  alias Jido.Integration.V2.Ingress.Definition
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.TriggerSpec

  @market_alert_trigger_id "market.alert.detected"
  @market_alert_signal_type @market_alert_trigger_id
  @market_alert_signal_source "/ingress/poll/market_data/#{@market_alert_trigger_id}"
  @market_alert_policy %{
    environment: %{allowed: [:prod]},
    sandbox: %{
      level: :standard,
      egress: :blocked,
      approvals: :auto,
      allowed_tools: ["market.feed.pull"]
    }
  }

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
          handler: Handler,
          input_schema:
            Zoi.object(%{
              symbol: Zoi.string(),
              limit: Zoi.integer(),
              venue: Zoi.string()
            }),
          output_schema:
            Zoi.object(%{
              symbol: Zoi.string(),
              venue: Zoi.string(),
              cursor: Zoi.integer(),
              items:
                Zoi.list(
                  Zoi.object(%{
                    seq: Zoi.integer(),
                    symbol: Zoi.string(),
                    venue: Zoi.string(),
                    bid: Zoi.number(),
                    ask: Zoi.number()
                  })
                ),
              auth_binding: Zoi.string()
            }),
          permissions: %{required_scopes: ["market:read"]},
          runtime: %{
            driver: "asm",
            provider: :claude,
            options: %{}
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
          consumer_surface: %{
            mode: :common,
            normalized_id: "market.ticks.pull",
            action_name: "market_ticks_pull"
          },
          schema_policy: %{
            input: :defined,
            output: :defined
          },
          jido: %{action: %{name: "market_ticks_pull"}},
          metadata: %{
            runtime_family: %{
              session_affinity: :target,
              resumable: false,
              approval_required: false,
              stream_capable: true,
              lifecycle_owner: :asm,
              runtime_ref: :session
            }
          }
        })
      ],
      triggers: [
        TriggerSpec.new!(%{
          trigger_id: @market_alert_trigger_id,
          name: "market_alert_detected",
          display_name: "Market alert detected",
          description: "Admits a common projected polling alert before downstream pulls run",
          runtime_class: :direct,
          delivery_mode: :poll,
          polling: %{default_interval_ms: 60_000, min_interval_ms: 5_000, jitter: false},
          handler: AlertTriggerHandler,
          config_schema:
            Zoi.object(%{
              interval_ms: Zoi.integer() |> Zoi.default(60_000)
            }),
          signal_schema:
            Zoi.object(%{
              symbol: Zoi.string(),
              price: Zoi.number(),
              threshold: Zoi.number(),
              direction: Zoi.string()
            }),
          permissions: %{required_scopes: ["market:read"]},
          checkpoint: %{strategy: :cursor},
          dedupe: %{strategy: :event_id},
          verification: %{},
          policy: @market_alert_policy,
          consumer_surface: %{
            mode: :common,
            normalized_id: "market.alerts.detected",
            sensor_name: "market_alerts_detected"
          },
          schema_policy: %{config: :defined, signal: :defined},
          jido: %{
            sensor: %{
              name: "market_alert_sensor",
              signal_type: @market_alert_signal_type,
              signal_source: @market_alert_signal_source
            }
          }
        })
      ],
      runtime_families: [:direct, :stream]
    })
  end

  @spec market_alert_definition() :: Definition.t()
  def market_alert_definition do
    manifest()
    |> Manifest.fetch_trigger(@market_alert_trigger_id)
    |> then(&Definition.from_trigger!("market_data", &1))
  end

  @spec ingress_definitions() :: [Definition.t()]
  def ingress_definitions do
    [market_alert_definition()]
  end
end
