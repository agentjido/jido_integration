defmodule Jido.Integration.V2.Auth.Stores do
  @moduledoc false

  alias Jido.Integration.V2.Auth.Persistence

  @spec credential_store() :: module()
  def credential_store do
    configured_store(:credential_store)
  end

  @spec lease_store() :: module()
  def lease_store do
    configured_store(:lease_store)
  end

  @spec connection_store() :: module()
  def connection_store do
    configured_store(:connection_store)
  end

  @spec install_store() :: module()
  def install_store do
    configured_store(:install_store)
  end

  defp configured_store(key) do
    case Application.fetch_env(:jido_integration_v2_auth, key) do
      {:ok, store} -> store
      :error -> Persistence.store_module(key)
    end
  end
end
