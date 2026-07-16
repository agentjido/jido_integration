defmodule Jido.Integration.V2.Auth.ManagedAccountStore do
  @moduledoc "Durable managed-account and credential-generation store behaviour."

  alias Jido.Integration.V2.Auth.ManagedAccount
  alias Jido.Integration.V2.Auth.ManagedCredentialVersion

  @callback transact((-> result)) :: result | {:error, term()} when result: term()
  @callback register(ManagedAccount.t(), ManagedCredentialVersion.t()) ::
              :ok | {:error, term()}
  @callback fetch(String.t()) :: {:ok, ManagedAccount.t()} | {:error, :unknown_managed_account}
  @callback lock(String.t()) :: {:ok, ManagedAccount.t()} | {:error, term()}
  @callback fetch_by_connection(String.t()) ::
              {:ok, ManagedAccount.t()} | {:error, :unknown_managed_account}
  @callback fetch_version(String.t(), pos_integer()) ::
              {:ok, ManagedCredentialVersion.t()} | {:error, :unknown_credential_generation}
  @callback rotate(
              String.t(),
              pos_integer(),
              non_neg_integer(),
              ManagedCredentialVersion.t(),
              DateTime.t()
            ) :: {:ok, ManagedAccount.t()} | {:error, term()}
  @callback revoke(String.t(), pos_integer(), non_neg_integer(), String.t(), DateTime.t()) ::
              {:ok, ManagedAccount.t()} | {:error, term()}
end
