defmodule Jido.Integration.Auth.Store do
  @moduledoc """
  Credential store behaviour.

  Defines the interface for pluggable credential storage backends.
  The repo ships ETS and disk adapters for deterministic tests, local
  development, and local durability proofs.
  """

  alias Jido.Integration.Auth.Credential

  @type auth_ref :: String.t()

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback store(server :: GenServer.server(), auth_ref(), Credential.t()) :: :ok
  @callback fetch(server :: GenServer.server(), auth_ref(), keyword()) ::
              {:ok, Credential.t()} | {:error, :not_found | :expired | :scope_violation}
  @callback delete(server :: GenServer.server(), auth_ref()) :: :ok | {:error, :not_found}
  @callback list(server :: GenServer.server(), connector_type :: String.t()) ::
              [{auth_ref(), Credential.t()}]
end
