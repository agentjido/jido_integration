defmodule Jido.Integration.V2.Connectors.MarketData.Generated.Sensors do
  @moduledoc false
end

alias Jido.Integration.V2.Connectors.MarketData
alias Jido.Integration.V2.ConsumerProjection
alias Jido.Integration.V2.TriggerSpec

for trigger <- MarketData.manifest().triggers,
    TriggerSpec.common_consumer_surface?(trigger) do
  connector = MarketData
  module = ConsumerProjection.sensor_module(connector, trigger)

  body =
    quote do
      @moduledoc false

      use Jido.Integration.V2.GeneratedSensor,
        connector: unquote(connector),
        trigger_id: unquote(trigger.trigger_id)
    end

  Module.create(module, body, Macro.Env.location(__ENV__))
end
