defmodule Jido.Integration.V2.Connectors.GitHub.Generated.Actions do
  @moduledoc false
end

alias Jido.Integration.V2.Connectors.GitHub
alias Jido.Integration.V2.ConsumerProjection

for operation <- GitHub.manifest().operations do
  connector = GitHub
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
