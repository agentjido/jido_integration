defmodule Jido.Integration.Secrets.Provider do
  @moduledoc """
  Behaviour for scoped credential materialization.

  Provider implementations convert a lease ref and a non-secret scope into a
  short-lived secret handle. Public callers receive only lease, provider, and
  audit refs. Raw material exists only inside a brokered adapter call.
  """

  alias Jido.Integration.Secrets.SecretHandle

  @type lease_ref :: String.t()
  @type binding_ref :: String.t()
  @type scope :: map()
  @type secret_opts :: keyword()
  @type receipt :: map()

  @callback materialize(lease_ref(), scope(), secret_opts()) ::
              {:ok, SecretHandle.t()} | {:error, term()}

  @callback rotate(binding_ref(), secret_opts()) :: {:ok, receipt()} | {:error, term()}

  @callback revoke(lease_ref(), secret_opts()) :: {:ok, receipt()} | {:error, term()}

  @callback audit_ref(SecretHandle.t() | map()) :: String.t()
end
