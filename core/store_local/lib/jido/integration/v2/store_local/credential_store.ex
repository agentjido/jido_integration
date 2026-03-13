defmodule Jido.Integration.V2.StoreLocal.CredentialStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.CredentialStore

  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage

  @impl true
  def store_credential(%Credential{} = credential) do
    Storage.mutate(&State.store_credential(&1, credential))
  end

  @impl true
  def fetch_credential(credential_id) do
    Storage.read(&State.fetch_credential(&1, credential_id))
  end

  def reset! do
    Storage.mutate(&State.reset_credentials/1)
  end
end
