defmodule Jido.Integration.V2.Auth.LeaseStore do
  @moduledoc """
  Durable credential-lease behaviour owned by `auth`.
  """

  alias Jido.Integration.V2.Auth.LeaseRecord

  @callback store_lease(LeaseRecord.t()) :: :ok | {:error, term()}
  @callback fetch_lease(String.t()) :: {:ok, LeaseRecord.t()} | {:error, :unknown_lease}
end
