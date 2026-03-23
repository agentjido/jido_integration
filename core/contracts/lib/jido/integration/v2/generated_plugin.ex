defmodule Jido.Integration.V2.GeneratedPlugin do
  @moduledoc """
  Macro for generating a connector-level `Jido.Plugin` bundle from an authored manifest.
  """

  alias Jido.Integration.V2.ConsumerProjection

  defmacro __using__(opts_ast) do
    {opts, _binding} = Code.eval_quoted(opts_ast, [], __CALLER__)
    connector_module = Keyword.fetch!(opts, :connector)
    consumer_projection = ConsumerProjection

    projection = ConsumerProjection.plugin_projection!(connector_module)
    plugin_opts = ConsumerProjection.plugin_opts(projection)

    quote do
      use Jido.Plugin, unquote(Macro.escape(plugin_opts))

      @generated_plugin_projection unquote(Macro.escape(projection))

      @doc false
      def generated_plugin_projection, do: @generated_plugin_projection

      defoverridable plugin_spec: 1

      @impl Jido.Plugin
      def subscriptions(config, context) do
        unquote(consumer_projection).plugin_subscriptions(
          @generated_plugin_projection,
          config,
          context
        )
      end

      @impl Jido.Plugin
      def plugin_spec(config) do
        spec = super(config)

        %{
          spec
          | actions:
              unquote(consumer_projection).filtered_actions!(
                @generated_plugin_projection,
                config
              )
        }
      end
    end
  end
end
