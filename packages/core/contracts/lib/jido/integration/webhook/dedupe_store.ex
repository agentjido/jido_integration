defmodule Jido.Integration.Webhook.DedupeStore do
  @moduledoc """
  Durable dedupe-key store behaviour.
  """

  @type entry :: %{key: String.t(), expires_at_ms: non_neg_integer()}

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback put(GenServer.server(), String.t(), non_neg_integer()) :: :ok
  @callback fetch(GenServer.server(), String.t(), keyword()) ::
              {:ok, entry()} | {:error, :not_found | :expired}
  @callback delete(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  @callback list(GenServer.server()) :: [entry()]
end
