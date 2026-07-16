defmodule Jido.Integration.Secrets.ManagedCredentialMaterializer do
  @moduledoc """
  Production bridge from a Jido managed-account lease to a configured secret provider.

  Provider endpoint and token loaders are materialized into application config at
  boot. Durable account truth contains only provider and binding refs. Raw
  provider material exists in the caller's bounded Auth materialization task.
  """

  @behaviour Jido.Integration.V2.CredentialMaterializer

  alias Jido.Integration.Secrets.SecretHandle
  alias Jido.Integration.Secrets.VaultKVProvider
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.MaterializationRequest
  alias Jido.Integration.V2.SecretMaterial

  @config_key :managed_providers

  @impl true
  def materialize(%CredentialLease{} = lease, %MaterializationRequest{} = request) do
    with {:ok, account} <- Auth.fetch_managed_account(request.account),
         {:ok, provider, provider_opts} <- provider_config(account.secret_provider_ref),
         {:ok, scope} <- managed_scope(provider, account, lease, request),
         {:ok, %SecretHandle{} = handle} <-
           materialize_handle(provider, lease.lease_id, scope, provider_opts),
         :ok <- ensure_handle_lease(handle, lease),
         {:ok, %SecretMaterial{} = material} <-
           SecretMaterial.new(%{
             materialization_ref: request.materialization_ref,
             provider_family: account.provider_family,
             account_ref: account.account_ref,
             generation: account.generation,
             payload: SecretHandle.material(handle)
           }) do
      Process.put(cleanup_key(request.materialization_ref), %{
        provider: provider,
        provider_opts: provider_opts,
        lease_id: lease.lease_id
      })

      {:ok, material}
    end
  end

  @impl true
  def revoke(%SecretMaterial{} = material, _opts) do
    case Process.delete(cleanup_key(material.materialization_ref)) do
      %{provider: provider, provider_opts: provider_opts, lease_id: lease_id} ->
        case provider.revoke(lease_id, provider_opts) do
          {:ok, _safe_receipt} -> :ok
          :ok -> :ok
          {:error, _reason} -> {:error, :managed_secret_revocation_failed}
          _other -> {:error, :invalid_secret_revocation_response}
        end

      nil ->
        :ok
    end
  end

  defp provider_config(provider_ref) do
    config = Application.get_env(:jido_integration_secrets_provider, @config_key, %{})
    provider_key = URI.parse(provider_ref).scheme

    case Map.get(config, provider_ref, Map.get(config, provider_key)) do
      opts when is_list(opts) -> normalize_provider_config(provider_ref, opts)
      %{} = opts -> normalize_provider_config(provider_ref, Map.to_list(opts))
      _missing -> {:error, {:managed_secret_provider_not_configured, provider_ref}}
    end
  end

  defp normalize_provider_config(provider_ref, opts) do
    provider = Keyword.get(opts, :provider, provider_for(provider_ref))
    provider_opts = Keyword.delete(opts, :provider)

    if valid_provider?(provider),
      do: {:ok, provider, provider_opts},
      else: {:error, {:managed_secret_provider_unavailable, provider_ref}}
  end

  defp provider_for("vault://" <> _rest), do: VaultKVProvider
  defp provider_for(_provider_ref), do: nil

  defp valid_provider?(provider) when is_atom(provider) do
    Code.ensure_loaded?(provider) and function_exported?(provider, :materialize, 3) and
      function_exported?(provider, :managed_scope, 3) and
      function_exported?(provider, :revoke, 2)
  end

  defp valid_provider?(_provider), do: false

  defp managed_scope(provider, account, lease, request) do
    case provider.managed_scope(
           Map.from_struct(account),
           Map.from_struct(lease),
           Map.from_struct(request)
         ) do
      {:ok, %{} = scope} -> {:ok, scope}
      {:error, _reason} -> {:error, :managed_secret_scope_invalid}
      _other -> {:error, :managed_secret_scope_invalid}
    end
  end

  defp materialize_handle(provider, lease_id, scope, provider_opts) do
    case provider.materialize(lease_id, scope, provider_opts) do
      {:ok, %SecretHandle{} = handle} -> {:ok, handle}
      {:error, _reason} -> {:error, :managed_secret_materialization_failed}
      _other -> {:error, :managed_secret_materialization_failed}
    end
  end

  defp ensure_handle_lease(%SecretHandle{lease_ref: lease_id}, %CredentialLease{
         lease_id: lease_id
       }),
       do: :ok

  defp ensure_handle_lease(_handle, _lease), do: {:error, :secret_handle_lease_mismatch}

  defp cleanup_key(materialization_ref), do: {__MODULE__, :cleanup, materialization_ref}
end
