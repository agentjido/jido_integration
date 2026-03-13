defmodule Jido.Integration.V2.Auth.Stores do
  @moduledoc false

  @default_store Jido.Integration.V2.Auth.Store

  @spec credential_store() :: module()
  def credential_store do
    Application.get_env(:jido_integration_v2_auth, :credential_store, @default_store)
  end

  @spec lease_store() :: module()
  def lease_store do
    Application.get_env(:jido_integration_v2_auth, :lease_store, @default_store)
  end

  @spec connection_store() :: module()
  def connection_store do
    Application.get_env(:jido_integration_v2_auth, :connection_store, @default_store)
  end

  @spec install_store() :: module()
  def install_store do
    Application.get_env(:jido_integration_v2_auth, :install_store, @default_store)
  end
end
