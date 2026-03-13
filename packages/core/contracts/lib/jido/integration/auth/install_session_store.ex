defmodule Jido.Integration.Auth.InstallSessionStore do
  @moduledoc """
  Durable install-session store behaviour with consume-once semantics.
  """

  alias Jido.Integration.Auth.InstallSession

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback put(GenServer.server(), InstallSession.t()) :: :ok
  @callback fetch(GenServer.server(), String.t(), keyword()) ::
              {:ok, InstallSession.t()} | {:error, :not_found | :expired}
  @callback consume(GenServer.server(), String.t()) ::
              {:ok, InstallSession.t()}
              | {:error, :not_found | :expired | :already_consumed}
  @callback delete(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  @callback list(GenServer.server()) :: [InstallSession.t()]
end
