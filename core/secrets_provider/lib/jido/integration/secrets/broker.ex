defmodule Jido.Integration.Secrets.Broker do
  @moduledoc """
  Executes lower adapter calls with scoped credential material.
  """

  alias Jido.Integration.Secrets.SecretHandle

  @type broker_fun :: (map(), map() -> {:ok, term()} | {:error, term()} | term())

  @spec with_materialized(module(), String.t(), map(), broker_fun(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def with_materialized(provider, lease_ref, scope, fun, opts \\ [])

  def with_materialized(provider, lease_ref, scope, fun, opts)
      when is_atom(provider) and is_binary(lease_ref) and is_map(scope) and is_function(fun, 2) and
             is_list(opts) do
    with :ok <- ensure_provider(provider),
         {:ok, %SecretHandle{} = handle} <- provider.materialize(lease_ref, scope, opts) do
      public_ref = SecretHandle.public_ref(handle)
      normalize_result(fun.(SecretHandle.material(handle), public_ref))
    end
  end

  def with_materialized(_provider, _lease_ref, _scope, _fun, _opts),
    do: {:error, :invalid_secret_broker_request}

  @spec public_receipt(SecretHandle.t() | map(), atom() | String.t()) :: map()
  def public_receipt(%SecretHandle{} = handle, disposition) do
    handle
    |> SecretHandle.public_ref()
    |> Map.put(:disposition, disposition)
    |> Map.put(:secret_material_redacted?, true)
  end

  def public_receipt(%{} = public_ref, disposition) do
    public_ref
    |> Map.take([:lease_ref, :provider_ref, :audit_ref, "lease_ref", "provider_ref", "audit_ref"])
    |> Map.put(:disposition, disposition)
    |> Map.put(:secret_material_redacted?, true)
  end

  defp ensure_provider(provider) do
    if Code.ensure_loaded?(provider) and function_exported?(provider, :materialize, 3) do
      :ok
    else
      {:error, {:secret_provider_unavailable, provider}}
    end
  end

  defp normalize_result({:ok, result}), do: {:ok, result}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result(result), do: {:ok, result}
end
