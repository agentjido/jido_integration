defmodule Jido.Integration.V2.Connectors.MarketData.Generated.Actions do
  @moduledoc false
end

alias Jido.Integration.V2.Connectors.MarketData
alias Jido.Integration.V2.ConsumerProjection
alias Jido.Integration.V2.OperationSpec

for operation <- MarketData.manifest().operations,
    OperationSpec.common_consumer_surface?(operation) do
  connector = MarketData
  module = ConsumerProjection.action_module(connector, operation)

  body =
    quote do
      @moduledoc false

      use Jido.Integration.V2.GeneratedAction,
        connector: unquote(connector),
        operation_id: unquote(operation.operation_id)
    end

  Module.create(module, body, Macro.Env.location(__ENV__))
end
