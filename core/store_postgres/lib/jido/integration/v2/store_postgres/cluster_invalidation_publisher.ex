defmodule Jido.Integration.V2.StorePostgres.ClusterInvalidationPublisher do
  @moduledoc """
  Configurable fanout publisher for memory cluster invalidation messages.
  """

  alias Jido.Integration.V2.ClusterInvalidation

  @app :jido_integration_v2_store_postgres
  @env_key :cluster_invalidation_publisher
  @telemetry_event [:jido_integration, :cluster_invalidation, :publish]

  @spec publish(ClusterInvalidation.t()) :: :ok | {:error, term()}
  def publish(%ClusterInvalidation{} = message) do
    case Application.get_env(@app, @env_key) do
      nil ->
        telemetry_publish(message)

      {:phoenix_pubsub, pubsub_name} ->
        phoenix_pubsub_publish(pubsub_name, message)

      {module, function} when is_atom(module) and is_atom(function) ->
        apply(module, function, [message])

      {module, function, extra_args}
      when is_atom(module) and is_atom(function) and is_list(extra_args) ->
        apply(module, function, [message | extra_args])

      module when is_atom(module) ->
        module.publish(message)
    end
  end

  @spec publish_all([ClusterInvalidation.t()]) :: :ok | {:error, term()}
  def publish_all(messages) when is_list(messages) do
    Enum.reduce_while(messages, :ok, fn message, :ok ->
      case publish(message) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp phoenix_pubsub_publish(pubsub_name, %ClusterInvalidation{} = message) do
    with :ok <-
           Phoenix.PubSub.broadcast(pubsub_name, message.topic, {:cluster_invalidation, message}) do
      telemetry_publish(message)
    end
  end

  defp telemetry_publish(%ClusterInvalidation{} = message) do
    :telemetry.execute(@telemetry_event, %{count: 1}, %{
      topic: message.topic,
      message: message
    })

    :ok
  end
end
