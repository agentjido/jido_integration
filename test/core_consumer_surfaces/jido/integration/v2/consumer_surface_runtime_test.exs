defmodule Jido.Integration.V2.ConsumerSurfaceRuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.ConsumerSurfaceRuntime
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.GeneratedPlugin
  alias Jido.Integration.V2.GeneratedSensor
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord
  alias Jido.Integration.V2.TriggerSpec

  defmodule Handler do
    def run(_input, _context), do: {:ok, %{}}
  end

  defmodule CommonTriggerConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "market_signals",
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
            display_name: "Market Signals",
            description: "Connector with a projected polling trigger",
            category: "market_data",
            tags: ["market"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [],
        triggers: [
          TriggerSpec.new!(%{
            trigger_id: "market.tick.detected",
            name: "market_tick_detected",
            display_name: "Market tick detected",
            description: "Projects a normalized market tick signal",
            runtime_class: :direct,
            delivery_mode: :poll,
            polling: %{default_interval_ms: 60_000, min_interval_ms: 5_000, jitter: false},
            handler: Handler,
            config_schema:
              Zoi.object(%{
                interval_ms: Zoi.integer() |> Zoi.default(60_000)
              }),
            signal_schema:
              Zoi.object(%{
                symbol: Zoi.string(),
                price: Zoi.number()
              }),
            permissions: %{required_scopes: ["market:read"]},
            checkpoint: %{strategy: :cursor, partition_key: "workspace"},
            dedupe: %{strategy: :event_id},
            verification: %{},
            consumer_surface: %{
              mode: :common,
              normalized_id: "market.ticks.detected",
              sensor_name: "market_ticks_detected"
            },
            schema_policy: %{config: :defined, signal: :defined},
            jido: %{
              sensor: %{
                name: "market_tick_sensor",
                signal_type: "market.tick.detected",
                signal_source: "/sensors/market/ticks"
              }
            }
          })
        ],
        runtime_families: [:direct]
      })
    end
  end

  defmodule CommonTriggerConnector.Generated.Sensors.MarketTicksDetected do
    use GeneratedSensor,
      connector: Jido.Integration.V2.ConsumerSurfaceRuntimeTest.CommonTriggerConnector,
      trigger_id: "market.tick.detected"
  end

  defmodule CommonTriggerConnector.Generated.Plugin do
    use GeneratedPlugin,
      connector: Jido.Integration.V2.ConsumerSurfaceRuntimeTest.CommonTriggerConnector
  end

  defmodule WebhookConnector do
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
            display_name: "GitHub Webhook",
            description: "Connector with a projected webhook trigger",
            category: "developer_tools",
            tags: ["github", "webhook"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [],
        triggers: [
          TriggerSpec.new!(%{
            trigger_id: "github.issue.opened",
            name: "issue_opened",
            display_name: "Issue opened",
            description: "Projects a normalized GitHub issue-opened signal",
            runtime_class: :direct,
            delivery_mode: :webhook,
            handler: Handler,
            config_schema:
              Contracts.strict_object!(
                [],
                description: "Normalized webhook subscription configuration"
              ),
            signal_schema:
              Zoi.object(%{
                action: Zoi.string(),
                issue_id: Zoi.integer()
              }),
            permissions: %{required_scopes: []},
            checkpoint: %{},
            dedupe: %{},
            verification: %{secret_name: "webhook_secret"},
            consumer_surface: %{
              mode: :common,
              normalized_id: "github.issue.opened",
              sensor_name: "github_issue_opened"
            },
            schema_policy: %{config: :defined, signal: :defined},
            jido: %{
              sensor: %{
                name: "github_issue_opened_sensor",
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

  defmodule FakeCapabilityInvoker do
    def invoke("market.tick.detected", input, opts) do
      send(self(), {:poll_invoke, input, opts})

      {:ok,
       %{
         output: %{
           signals: [%{symbol: "AAPL", price: 201.25}],
           dedupe_keys: ["tick-1"],
           checkpoint: %{cursor: "cursor-1", last_event_time: "cursor-1"}
         }
       }}
    end
  end

  defmodule FakeCheckpointOnlyInvoker do
    def invoke("market.tick.detected", input, opts) do
      send(self(), {:poll_invoke, input, opts})

      {:ok,
       %{
         output: %{
           signals: [],
           checkpoint: %{cursor: "cursor-2", last_event_time: "cursor-2"}
         }
       }}
    end
  end

  defmodule FakeIngress do
    def admit_poll(request, definition) do
      send(self(), {:admit_poll, request, definition})
      {:ok, %{status: :accepted}}
    end
  end

  defmodule FakeControlPlane do
    def fetch_trigger_checkpoint(_tenant_id, _connector_id, _trigger_id, _partition_key),
      do: :error

    def put_trigger_checkpoint(%TriggerCheckpoint{} = checkpoint) do
      send(self(), {:put_checkpoint, checkpoint})
      :ok
    end
  end

  test "generated poll sensors validate runtime config, schedule ticks, and emit stable signals" do
    sensor_module = CommonTriggerConnector.Generated.Sensors.MarketTicksDetected

    assert {:ok, config} =
             Zoi.parse(sensor_module.schema(), %{
               connection_id: "conn-market-1",
               tenant_id: "tenant-market-1",
               partition_key: "workspace"
             })

    assert {:ok, state, [{:schedule, 60_000}]} =
             sensor_module.init(config, %{
               consumer_runtime: %{
                 capability_invoker: FakeCapabilityInvoker,
                 ingress: FakeIngress,
                 control_plane: FakeControlPlane
               }
             })

    assert {:ok, ^state, [{:emit, signal}, {:schedule, 60_000}]} =
             sensor_module.handle_event(:tick, state)

    assert_receive {:poll_invoke, %{}, opts}
    assert opts[:connection_id] == "conn-market-1"
    assert opts[:tenant_id] == "tenant-market-1"
    assert opts[:environment] == :prod
    assert opts[:allowed_operations] == ["market.tick.detected"]
    refute Keyword.has_key?(opts, :extensions)

    assert_receive {:admit_poll, request, definition}
    assert request.tenant_id == "tenant-market-1"
    assert request.partition_key == "workspace"
    assert request.cursor == "cursor-1"
    assert request.external_id == "tick-1"
    assert is_nil(request.last_event_time)
    assert definition.trigger_id == "market.tick.detected"

    assert signal.type == "market.tick.detected"
    assert signal.source == "/sensors/market/ticks"
    assert signal.data == %{symbol: "AAPL", price: 201.25}
  end

  test "generated poll sensors persist checkpoints when a poll advances without emitted signals" do
    sensor_module = CommonTriggerConnector.Generated.Sensors.MarketTicksDetected

    {:ok, config} =
      Zoi.parse(sensor_module.schema(), %{
        connection_id: "conn-market-1",
        tenant_id: "tenant-market-1",
        partition_key: "workspace"
      })

    {:ok, state, [{:schedule, 60_000}]} =
      sensor_module.init(config, %{
        consumer_runtime: %{
          capability_invoker: FakeCheckpointOnlyInvoker,
          ingress: FakeIngress,
          control_plane: FakeControlPlane
        }
      })

    assert {:ok, ^state, [{:schedule, 60_000}]} = sensor_module.handle_event(:tick, state)

    assert_receive {:put_checkpoint, checkpoint}
    assert checkpoint.tenant_id == "tenant-market-1"
    assert checkpoint.connector_id == "market_signals"
    assert checkpoint.trigger_id == "market.tick.detected"
    assert checkpoint.partition_key == "workspace"
    assert checkpoint.cursor == "cursor-2"
    assert is_nil(checkpoint.last_event_time)
  end

  test "generated plugin subscriptions materialize configured poll sensors with invoke defaults" do
    plugin = CommonTriggerConnector.Generated.Plugin
    sensor_module = CommonTriggerConnector.Generated.Sensors.MarketTicksDetected

    assert plugin.subscriptions(%{}, %{agent_id: "agent-market-1"}) == []

    assert [{^sensor_module, sensor_config}] =
             plugin.subscriptions(
               %{
                 connection_id: "conn-market-1",
                 invoke_defaults: %{
                   tenant_id: "tenant-market-1",
                   actor_id: "actor-market-1",
                   environment: :staging,
                   extensions: %{workspace: "ops"}
                 },
                 trigger_subscriptions: %{
                   market_ticks_detected: %{
                     enabled: true,
                     interval_ms: 45_000,
                     partition_key: "workspace",
                     config: %{interval_ms: 5_000}
                   }
                 }
               },
               %{agent_id: "agent-market-1"}
             )

    assert sensor_config == %{
             actor_id: "actor-market-1",
             config: %{interval_ms: 5_000},
             connection_id: "conn-market-1",
             environment: :staging,
             extensions: %{workspace: "ops"},
             interval_ms: 45_000,
             partition_key: "workspace",
             tenant_id: "tenant-market-1"
           }
  end

  test "webhook helpers project trigger records into stable Jido signals" do
    trigger =
      TriggerRecord.new!(%{
        source: :webhook,
        connector_id: "github",
        trigger_id: "github.issue.opened",
        capability_id: "github.issue.opened",
        tenant_id: "tenant-github-1",
        external_id: "delivery-1",
        dedupe_key: "delivery-1",
        payload: %{action: "opened", issue_id: 42},
        signal: %{}
      })

    signal = ConsumerSurfaceRuntime.webhook_signal!(WebhookConnector, trigger)

    assert signal.type == "github.issue.opened"
    assert signal.source == "/ingress/webhook/github/issues.opened"
    assert signal.data == %{action: "opened", issue_id: 42}
  end
end
