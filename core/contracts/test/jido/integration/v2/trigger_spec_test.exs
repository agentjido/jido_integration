defmodule Jido.Integration.V2.TriggerSpecTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.TriggerSpec

  defmodule Handler do
    def run(_input, _context), do: {:ok, %{}}
  end

  test "common projected triggers require deterministic sensor signal metadata" do
    common_trigger_attrs = %{
      trigger_id: "market.tick.detected",
      name: "market_tick_detected",
      display_name: "Market tick detected",
      description: "Emits a normalized market tick signal",
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
          signal_source: "/sensors/market/ticks"
        }
      }
    }

    assert_raise ArgumentError,
                 ~r/trigger.jido.sensor.signal_type is required for common projected surfaces/,
                 fn ->
                   TriggerSpec.new!(common_trigger_attrs)
                 end

    assert_raise ArgumentError,
                 ~r/trigger.jido.sensor.signal_source is required for common projected surfaces/,
                 fn ->
                   TriggerSpec.new!(
                     put_in(common_trigger_attrs, [:jido, :sensor], %{
                       name: "market_tick_sensor",
                       signal_type: "market.tick.detected"
                     })
                   )
                 end
  end

  test "connector-local triggers keep signal metadata optional" do
    trigger =
      TriggerSpec.new!(%{
        trigger_id: "market.tick.ingest",
        name: "market_tick_ingest",
        display_name: "Market tick ingest",
        description: "Keeps a provider-specific trigger outside the common surface",
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
          reason: "Provider-specific polling stays connector-local"
        },
        schema_policy: %{
          config: :passthrough,
          signal: :passthrough,
          justification:
            "Connector-local polling can keep its passthrough contract until it is intentionally projected"
        },
        jido: %{sensor: %{name: "market_tick_ingest"}}
      })

    assert TriggerSpec.connector_local_consumer_surface?(trigger)
    assert TriggerSpec.sensor_signal_type(trigger) == nil
    assert TriggerSpec.sensor_signal_source(trigger) == nil
  end
end
