defmodule Jido.Integration.V2.Auth.ConnectionStore do
  @moduledoc """
  Durable connection-truth behaviour owned by `auth`.
  """

  alias Jido.Integration.V2.Auth.Connection

  @callback store_connection(Connection.t()) :: :ok | {:error, term()}
  @callback fetch_connection(String.t()) :: {:ok, Connection.t()} | {:error, :unknown_connection}
end
