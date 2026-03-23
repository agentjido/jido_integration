defmodule Jido.Integration.V2.GeneratedSensor do
  @moduledoc """
  Macro for generating a `Jido.Sensor` from an authored trigger spec.

  Generated sensors are derivative of authored trigger publication. They only
  exist for common consumer surfaces and do not turn connector-local trigger
  inventory into shared generated surface area by default.
  """

  alias Jido.Integration.V2.ConsumerProjection

  defmacro __using__(opts_ast) do
    {opts, _binding} = Code.eval_quoted(opts_ast, [], __CALLER__)
    connector_module = Keyword.fetch!(opts, :connector)
    trigger_id = Keyword.fetch!(opts, :trigger_id)
    consumer_projection = ConsumerProjection

    projection = ConsumerProjection.sensor_projection!(connector_module, trigger_id)
    sensor_opts = ConsumerProjection.sensor_opts(projection)

    quote do
      use Jido.Sensor, unquote(Macro.escape(sensor_opts))

      @generated_sensor_projection unquote(Macro.escape(projection))

      @doc false
      def generated_sensor_projection, do: @generated_sensor_projection

      @doc false
      def trigger_id, do: @generated_sensor_projection.trigger_id

      @impl Jido.Sensor
      def init(config, context) do
        unquote(consumer_projection).init_sensor(
          @generated_sensor_projection,
          config,
          context
        )
      end

      @impl Jido.Sensor
      def handle_event(event, state) do
        unquote(consumer_projection).handle_sensor_event(
          @generated_sensor_projection,
          event,
          state
        )
      end
    end
  end
end
