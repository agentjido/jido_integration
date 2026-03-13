defmodule Jido.Integration.Auth.ConnectionStore do
  @moduledoc """
  Durable connection store behaviour.
  """

  alias Jido.Integration.Auth.Connection

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback put(GenServer.server(), Connection.t()) :: :ok
  @callback fetch(GenServer.server(), String.t()) :: {:ok, Connection.t()} | {:error, :not_found}
  @callback delete(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  @callback list(GenServer.server()) :: [Connection.t()]
end
