defmodule Jido.Integration.V2.Auth.InstallStore do
  @moduledoc """
  Durable install-session behaviour owned by `auth`.
  """

  alias Jido.Integration.V2.Auth.Install

  @callback store_install(Install.t()) :: :ok | {:error, term()}
  @callback fetch_install(String.t()) :: {:ok, Install.t()} | {:error, :unknown_install}
end
