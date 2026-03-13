defmodule Jido.Integration.Dispatch.RunStore do
  @moduledoc """
  Durable run-record store behaviour.

  Backends preserve the logical identity of an execution run through `run_id`,
  support durable lookup by `idempotency_key`, and reject conflicting
  idempotency bindings for different `run_id` values.
  """

  alias Jido.Integration.Dispatch.Run

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback put(GenServer.server(), Run.t()) :: :ok | {:error, term()}
  @callback fetch(GenServer.server(), String.t()) :: {:ok, Run.t()} | {:error, :not_found}
  @callback fetch_by_idempotency(GenServer.server(), String.t()) ::
              {:ok, Run.t()} | {:error, :not_found}
  @callback list(GenServer.server()) :: [Run.t()]
  @callback list(GenServer.server(), keyword()) :: [Run.t()]
  @callback delete(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
end
