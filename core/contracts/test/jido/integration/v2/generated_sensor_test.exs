defmodule Jido.Integration.V2.GeneratedSensorTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.Manifest
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
            description: "Connector with projected and connector-local triggers",
            category: "market_data",
            tags: ["market"],
            docs_refs: ["https://docs.example.test/market-signals"],
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
            checkpoint: %{strategy: :cursor},
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
          }),
          TriggerSpec.new!(%{
            trigger_id: "market.tick.provider_raw",
            name: "market_tick_provider_raw",
            display_name: "Market tick provider raw",
            description: "Stays outside the common generated trigger surface",
            runtime_class: :direct,
            delivery_mode: :poll,
            handler: Handler,
            config_schema: Zoi.map(),
            signal_schema: Zoi.map(),
            permissions: %{required_scopes: ["market:read"]},
            checkpoint: %{},
            dedupe: %{},
            verification: %{},
            consumer_surface: %{
              mode: :connector_local,
              reason: "Provider-specific trigger semantics stay connector-local"
            },
            schema_policy: %{
              config: :passthrough,
              signal: :passthrough,
              justification:
                "Connector-local trigger passthrough keeps the long-tail provider surface explicit"
            },
            jido: %{sensor: %{name: "market_tick_provider_raw"}}
          })
        ],
        runtime_families: [:direct]
      })
    end
  end

  defmodule CommonTriggerConnector.Generated.Sensors.MarketTicksDetected do
    use Jido.Integration.V2.GeneratedSensor,
      connector: Jido.Integration.V2.GeneratedSensorTest.CommonTriggerConnector,
      trigger_id: "market.tick.detected"
  end

  defmodule CommonTriggerConnector.Generated.Plugin do
    use Jido.Integration.V2.GeneratedPlugin,
      connector: Jido.Integration.V2.GeneratedSensorTest.CommonTriggerConnector
  end

  defmodule DuplicateProjectedTriggerConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "duplicate_triggers",
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
            display_name: "Duplicate Triggers",
            description: "Connector with colliding generated trigger surfaces",
            category: "market_data",
            tags: ["market"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [],
        triggers: [
          duplicate_trigger("market.tick.detected", "first_tick_sensor"),
          duplicate_trigger("market.tick.updated", "second_tick_sensor")
        ],
        runtime_families: [:direct]
      })
    end

    defp duplicate_trigger(trigger_id, jido_name) do
      TriggerSpec.new!(%{
        trigger_id: trigger_id,
        name: String.replace(trigger_id, ".", "_"),
        display_name: trigger_id,
        description: "Duplicate projected trigger",
        runtime_class: :direct,
        delivery_mode: :poll,
        handler: Handler,
        config_schema:
          Zoi.object(%{
            interval_ms: Zoi.integer() |> Zoi.default(60_000)
          }),
        signal_schema:
          Zoi.object(%{
            symbol: Zoi.string()
          }),
        permissions: %{required_scopes: ["market:read"]},
        checkpoint: %{},
        dedupe: %{},
        verification: %{},
        consumer_surface: %{
          mode: :common,
          normalized_id: "market.ticks.detected",
          sensor_name: "market_ticks_detected"
        },
        schema_policy: %{config: :defined, signal: :defined},
        jido: %{
          sensor: %{
            name: jido_name,
            signal_type: "market.tick.detected",
            signal_source: "/sensors/market/ticks"
          }
        }
      })
    end
  end

  test "derives deterministic sensor projection rules from the authored manifest" do
    projection =
      ConsumerProjection.sensor_projection!(CommonTriggerConnector, "market.tick.detected")

    [trigger | _rest] = CommonTriggerConnector.manifest().triggers

    assert projection.module ==
             CommonTriggerConnector.Generated.Sensors.MarketTicksDetected

    assert projection.plugin_module == CommonTriggerConnector.Generated.Plugin
    assert projection.trigger_id == "market.tick.detected"
    assert projection.normalized_id == "market.ticks.detected"
    assert projection.sensor_name == "market_ticks_detected"
    assert projection.jido_name == "market_tick_sensor"
    assert projection.description == trigger.description
    assert projection.category == "market_data"
    assert projection.tags == ["market", "market_signals", "poll"]
    assert projection.config_schema == trigger.config_schema
    assert projection.signal_schema == trigger.signal_schema
    assert projection.signal_type == "market.tick.detected"
    assert projection.signal_source == "/sensors/market/ticks"

    assert ConsumerProjection.sensor_opts(projection)[:name] == "market_tick_sensor"
    assert ConsumerProjection.sensor_opts(projection)[:schema] == trigger.config_schema

    assert %Jido.Signal{
             type: "market.tick.detected",
             source: "/sensors/market/ticks",
             data: %{symbol: "AAPL", price: 201.25}
           } = ConsumerProjection.sensor_signal!(projection, %{symbol: "AAPL", price: 201.25})
  end

  test "generated sensors target the real Jido.Sensor contract and emit deterministic signals" do
    sensor_module = CommonTriggerConnector.Generated.Sensors.MarketTicksDetected

    assert Code.ensure_loaded?(sensor_module)
    assert sensor_module.trigger_id() == "market.tick.detected"
    assert sensor_module.name() == "market_tick_sensor"

    assert {:ok, parsed_config} = Zoi.parse(sensor_module.schema(), %{})
    assert parsed_config.interval_ms == 60_000

    assert {:ok, state} = sensor_module.init(parsed_config, %{agent_id: "agent-market-1"})

    assert {:ok, ^state, [{:emit, %Jido.Signal{} = signal}]} =
             sensor_module.handle_event(%{symbol: "AAPL", price: 201.25}, state)

    assert signal.type == "market.tick.detected"
    assert signal.source == "/sensors/market/ticks"
    assert signal.data == %{symbol: "AAPL", price: 201.25}
  end

  test "generated plugin subscriptions derive from the trigger projection" do
    plugin = CommonTriggerConnector.Generated.Plugin
    sensor_module = CommonTriggerConnector.Generated.Sensors.MarketTicksDetected

    assert plugin.subscriptions() == [{sensor_module, %{}}]
    assert plugin.manifest().subscriptions == [{sensor_module, %{}}]

    assert plugin.subscriptions(%{connection_id: "conn-market-1"}, %{agent_id: "agent-market-1"}) ==
             [{sensor_module, %{}}]
  end

  test "projects only explicitly common trigger surfaces" do
    assert ConsumerProjection.sensor_modules(CommonTriggerConnector) == [
             CommonTriggerConnector.Generated.Sensors.MarketTicksDetected
           ]

    assert Enum.map(
             ConsumerProjection.projected_triggers(CommonTriggerConnector.manifest()),
             & &1.trigger_id
           ) == ["market.tick.detected"]

    assert_raise ArgumentError, ~r/not projected into the common consumer surface/, fn ->
      ConsumerProjection.sensor_projection!(CommonTriggerConnector, "market.tick.provider_raw")
    end
  end

  test "rejects manifests that collide on generated sensor modules or sensor names" do
    assert_raise ArgumentError,
                 ~r/generated consumer trigger projections must be unique within a connector/,
                 fn ->
                   ConsumerProjection.plugin_projection!(DuplicateProjectedTriggerConnector)
                 end
  end
end
