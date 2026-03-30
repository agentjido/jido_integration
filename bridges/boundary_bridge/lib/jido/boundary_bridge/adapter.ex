defmodule Jido.BoundaryBridge.Adapter do
  @moduledoc """
  Behaviour for lower-boundary adapters.

  Stage 2 keeps the adapter seam narrow so later `jido_os` wiring can land
  without changing the bridge's public contract.
  """

  @type payload :: map()
  @type adapter_opts :: keyword()

  @callback allocate(payload(), adapter_opts()) :: {:ok, map()} | {:error, term()}
  @callback reopen(payload(), adapter_opts()) :: {:ok, map()} | {:error, term()}
  @callback fetch_status(String.t(), adapter_opts()) :: {:ok, map()} | {:error, term()}
  @callback claim(String.t(), payload(), adapter_opts()) :: {:ok, map()} | {:error, term()}
  @callback heartbeat(String.t(), payload(), adapter_opts()) :: {:ok, map()} | {:error, term()}
  @callback stop(String.t(), adapter_opts()) :: :ok | {:error, term()}
end
