defmodule Jido.Integration.Webhook.RouteStore do
  @moduledoc """
  Durable webhook route store behaviour.
  """

  alias Jido.Integration.Webhook.Route

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback put(GenServer.server(), Route.t()) :: :ok
  @callback delete(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  @callback list(GenServer.server()) :: [Route.t()]
end
