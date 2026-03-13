defmodule Jido.Integration.Dispatch.Store do
  @moduledoc """
  Durable dispatch-record store behaviour.

  Backends preserve the logical identity of a dispatch transport record through
  `dispatch_id` and support filtered listing for recovery and operator queries.
  """

  alias Jido.Integration.Dispatch.Record

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback put(GenServer.server(), Record.t()) :: :ok | {:error, term()}
  @callback fetch(GenServer.server(), String.t()) :: {:ok, Record.t()} | {:error, :not_found}
  @callback list(GenServer.server()) :: [Record.t()]
  @callback list(GenServer.server(), keyword()) :: [Record.t()]
  @callback delete(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
end
