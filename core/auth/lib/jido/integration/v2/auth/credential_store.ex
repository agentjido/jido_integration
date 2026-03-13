defmodule Jido.Integration.V2.Auth.CredentialStore do
  @moduledoc """
  Durable credential-truth behaviour owned by `auth`.
  """

  alias Jido.Integration.V2.Credential

  @callback store_credential(Credential.t()) :: :ok | {:error, term()}
  @callback fetch_credential(String.t()) ::
              {:ok, Credential.t()} | {:error, :unknown_credential}
end
