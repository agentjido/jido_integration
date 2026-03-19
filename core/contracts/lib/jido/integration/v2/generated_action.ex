defmodule Jido.Integration.V2.GeneratedAction do
  @moduledoc """
  Macro for generating a `Jido.Action` from an authored operation spec.
  """

  alias Jido.Integration.V2.ConsumerProjection

  defmacro __using__(opts_ast) do
    {opts, _binding} = Code.eval_quoted(opts_ast, [], __CALLER__)
    connector_module = Keyword.fetch!(opts, :connector)
    operation_id = Keyword.fetch!(opts, :operation_id)
    consumer_projection = ConsumerProjection

    projection = ConsumerProjection.action_projection!(connector_module, operation_id)
    action_opts = ConsumerProjection.action_opts(projection)

    quote do
      use Jido.Action, unquote(Macro.escape(action_opts))

      @generated_action_projection unquote(Macro.escape(projection))

      @doc false
      def generated_action_projection, do: @generated_action_projection

      @doc false
      def operation_id, do: @generated_action_projection.operation_id

      @impl true
      def run(params, context) do
        unquote(consumer_projection).run_action(
          @generated_action_projection,
          params,
          context
        )
      end
    end
  end
end
