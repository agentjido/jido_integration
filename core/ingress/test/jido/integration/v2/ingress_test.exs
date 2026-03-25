defmodule Jido.Integration.V2.IngressTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.Ingress
  alias Jido.Integration.V2.Ingress.Definition
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.StorePostgres.TestSupport
  alias Jido.Integration.V2.TriggerSpec

  defmodule NoopHandler do
  end

  defmodule GitHubConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "github",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :oauth2,
            install: %{required: false},
            reauth: %{supported: false},
            requested_scopes: [],
            lease_fields: ["access_token"],
            secret_names: ["webhook_secret"]
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "GitHub Ingress Test",
            description: "Webhook ingress test connector",
            category: "test",
            tags: ["webhook"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [],
        triggers: [
          TriggerSpec.new!(%{
            trigger_id: "github.issue.ingest",
            name: "issue_ingest",
            display_name: "Issue ingest",
            description: "Receives webhook issue events",
            runtime_class: :direct,
            delivery_mode: :webhook,
            handler: NoopHandler,
            config_schema: Zoi.map(description: "Webhook config"),
            signal_schema: Zoi.map(description: "Webhook signal"),
            permissions: %{required_scopes: []},
            checkpoint: %{},
            dedupe: %{},
            verification: %{secret_name: "webhook_secret"},
            consumer_surface: %{
              mode: :connector_local,
              reason: "Ingress webhook proofs stay connector-local"
            },
            schema_policy: %{
              config: :passthrough,
              signal: :passthrough,
              justification:
                "Ingress tests preserve webhook payload passthrough because these triggers are not projected common consumer surfaces"
            },
            jido: %{
              sensor: %{
                name: "github_issue_ingest",
                signal_type: "github.issue.opened",
                signal_source: "/ingress/webhook/github/issues.opened"
              }
            }
          })
        ],
        runtime_families: [:direct]
      })
    end
  end

  defmodule MarketDataConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "market_data",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :api_token,
            install: %{required: false},
            reauth: %{supported: false},
            requested_scopes: ["market:read"],
            lease_fields: ["access_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Market Data Ingress Test",
            description: "Polling ingress test connector",
            category: "test",
            tags: ["poll"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [],
        triggers: [
          TriggerSpec.new!(%{
            trigger_id: "market.alert.detected",
            name: "market_alert_detected",
            display_name: "Market alert detected",
            description: "Receives poll alert events through the common trigger proof",
            runtime_class: :direct,
            delivery_mode: :poll,
            polling: %{default_interval_ms: 60_000, min_interval_ms: 5_000, jitter: false},
            handler: NoopHandler,
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
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :blocked,
                approvals: :auto,
                allowed_tools: ["market.feed.pull"]
              }
            },
            consumer_surface: %{
              mode: :common,
              normalized_id: "market.alerts.detected",
              sensor_name: "market_alerts_detected"
            },
            schema_policy: %{
              config: :defined,
              signal: :defined
            },
            jido: %{
              sensor: %{
                name: "market_alert_sensor",
                signal_type: "market.alert.detected",
                signal_source: "/ingress/poll/market_data/market.alert.detected"
              }
            }
          })
        ],
        runtime_families: [:direct]
      })
    end
  end

  setup do
    ControlPlane.reset!()
    assert :ok = ControlPlane.register_connector(GitHubConnector)
    assert :ok = ControlPlane.register_connector(MarketDataConnector)
    :ok
  end

  test "admits a signed webhook trigger and records trigger-to-run causation" do
    definition = webhook_definition()
    request = signed_webhook_request("delivery-1", %{action: "opened", issue: %{number: 42}})

    assert {:ok, result} = Ingress.admit_webhook(request, definition)
    assert result.status == :accepted
    assert result.run.status == :accepted
    assert result.trigger.run_id == result.run.run_id
    assert result.trigger.signal["type"] == "github.issue.opened"

    assert {:ok, recorded_trigger} =
             ControlPlane.fetch_trigger(
               "tenant-1",
               "github",
               "github.issue.ingest",
               "delivery-1"
             )

    assert recorded_trigger.run_id == result.run.run_id

    assert [%{type: "run.accepted"}] =
             Enum.map(ControlPlane.events(result.run.run_id), &%{type: &1.type})
  end

  test "does not create duplicate runs for replayed webhook deliveries" do
    definition = webhook_definition()
    request = signed_webhook_request("delivery-dup", %{action: "opened", issue: %{number: 7}})

    assert {:ok, first} = Ingress.admit_webhook(request, definition)
    assert {:ok, duplicate} = Ingress.admit_webhook(request, definition)

    assert first.status == :accepted
    assert duplicate.status == :duplicate
    assert duplicate.run.run_id == first.run.run_id
    assert length(ControlPlane.events(first.run.run_id)) == 1
  end

  test "rejects invalid signatures and records rejected trigger truth" do
    definition = webhook_definition()

    request =
      signed_webhook_request("delivery-bad-signature", %{action: "opened"})
      |> put_in([:headers, "x-hub-signature-256"], "sha256=deadbeef")

    assert {:error, error} = Ingress.admit_webhook(request, definition)
    assert error.reason == :signature_invalid
    assert error.trigger.status == :rejected
    assert is_nil(error.trigger.run_id)

    assert {:ok, rejected_trigger} =
             ControlPlane.fetch_trigger(
               "tenant-1",
               "github",
               "github.issue.ingest",
               "delivery-bad-signature"
             )

    assert rejected_trigger.status == :rejected
    assert rejected_trigger.rejection_reason == :signature_invalid
  end

  test "rejects invalid triggers before admission and records the rejection" do
    definition = webhook_definition()
    request = signed_webhook_request("delivery-invalid", %{issue: %{number: 13}})

    assert {:error, error} = Ingress.admit_webhook(request, definition)
    assert error.reason == {:invalid_trigger, :missing_action}
    assert error.trigger.status == :rejected

    assert {:ok, rejected_trigger} =
             ControlPlane.fetch_trigger(
               "tenant-1",
               "github",
               "github.issue.ingest",
               "delivery-invalid"
             )

    assert rejected_trigger.rejection_reason == {:invalid_trigger, :missing_action}
  end

  test "persists polling checkpoints and dedupe state across repo restarts" do
    definition = poll_definition()

    request = %{
      tenant_id: "tenant-1",
      external_id: "poll-event-1",
      partition_key: "AAPL",
      cursor: "cursor-1",
      last_event_id: "poll-event-1",
      last_event_time: ~U[2026-03-09 12:00:00Z],
      event: %{symbol: "AAPL", price: 201.25, threshold: 200.0, direction: "above"}
    }

    assert {:ok, first} = Ingress.admit_poll(request, definition)

    assert {:ok, checkpoint} =
             ControlPlane.fetch_trigger_checkpoint(
               "tenant-1",
               "market_data",
               "market.alert.detected",
               "AAPL"
             )

    assert checkpoint.cursor == "cursor-1"
    :ok = TestSupport.restart_repo!()

    assert {:ok, duplicate} = Ingress.admit_poll(request, definition)

    assert duplicate.status == :duplicate
    assert duplicate.run.run_id == first.run.run_id

    assert {:ok, persisted_checkpoint} =
             ControlPlane.fetch_trigger_checkpoint(
               "tenant-1",
               "market_data",
               "market.alert.detected",
               "AAPL"
             )

    assert persisted_checkpoint.cursor == "cursor-1"
  end

  test "derives poll ingress definitions from authored common trigger metadata" do
    trigger =
      TriggerSpec.new!(%{
        trigger_id: "market.alert.detected",
        name: "market_alert_detected",
        display_name: "Market alert detected",
        description: "Admits one authored market-alert polling trigger",
        runtime_class: :direct,
        delivery_mode: :poll,
        polling: %{default_interval_ms: 60_000, min_interval_ms: 5_000, jitter: false},
        handler: NoopHandler,
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
        consumer_surface: %{
          mode: :common,
          normalized_id: "market.alerts.detected",
          sensor_name: "market_alerts_detected"
        },
        schema_policy: %{config: :defined, signal: :defined},
        jido: %{
          sensor: %{
            name: "market_alert_sensor",
            signal_type: "market.alert.detected",
            signal_source: "/ingress/poll/market_data/market.alert.detected"
          }
        }
      })

    definition =
      Definition.from_trigger!("market_data", trigger, %{
        dedupe_ttl_seconds: 300
      })

    assert definition.source == :poll
    assert definition.connector_id == "market_data"
    assert definition.trigger_id == "market.alert.detected"
    assert definition.capability_id == "market.alert.detected"
    assert definition.signal_type == "market.alert.detected"
    assert definition.signal_source == "/ingress/poll/market_data/market.alert.detected"
    assert definition.dedupe_ttl_seconds == 300

    assert :ok ==
             definition.validator.(%{
               symbol: "AAPL",
               price: 201.25,
               threshold: 200.0,
               direction: "above"
             })

    assert match?({:error, _reason}, definition.validator.(%{symbol: "AAPL"}))
  end

  defp webhook_definition do
    trigger = GitHubConnector.manifest().triggers |> List.first()

    Definition.from_trigger!("github", trigger, %{
      dedupe_ttl_seconds: 86_400,
      verification: %{
        algorithm: :sha256,
        secret: "super-secret",
        signature_header: "x-hub-signature-256"
      },
      validator: &validate_issue_opened/1
    })
  end

  defp poll_definition do
    Definition.new!(%{
      source: :poll,
      connector_id: "market_data",
      trigger_id: "market.alert.detected",
      capability_id: "market.alert.detected",
      signal_type: "market.alert.detected",
      signal_source: "/ingress/poll/market_data/market.alert.detected",
      dedupe_ttl_seconds: 86_400,
      validator: &validate_market_alert/1
    })
  end

  defp signed_webhook_request(external_id, body) do
    raw_body = inspect(body)

    %{
      tenant_id: "tenant-1",
      external_id: external_id,
      raw_body: raw_body,
      body: body,
      headers: %{
        "x-hub-signature-256" => "sha256=" <> Base.encode16(signature(raw_body), case: :lower)
      }
    }
  end

  defp signature(raw_body) do
    :crypto.mac(:hmac, :sha256, "super-secret", raw_body)
  end

  defp validate_issue_opened(%{action: "opened"}), do: :ok
  defp validate_issue_opened(%{"action" => "opened"}), do: :ok
  defp validate_issue_opened(_payload), do: {:error, :missing_action}

  defp validate_market_alert(%{
         symbol: symbol,
         price: price,
         threshold: threshold,
         direction: direction
       })
       when is_binary(symbol) and is_number(price) and is_number(threshold) and
              is_binary(direction),
       do: :ok

  defp validate_market_alert(%{
         "symbol" => symbol,
         "price" => price,
         "threshold" => threshold,
         "direction" => direction
       })
       when is_binary(symbol) and is_number(price) and is_number(threshold) and
              is_binary(direction),
       do: :ok

  defp validate_market_alert(_payload), do: {:error, :invalid_market_alert}
end
