defmodule Jido.Integration.V2.Auth.ManagedAccount do
  @moduledoc "Durable, secret-free provider-account truth owned by Jido Auth."

  alias Jido.Integration.V2.ManagedAccountRef

  @enforce_keys [
    :provider_family,
    :account_ref,
    :tenant_id,
    :connection_id,
    :endpoint_ref,
    :quota_scope_ref,
    :generation,
    :fence,
    :credential_handle_ref,
    :secret_provider_ref,
    :secret_binding_ref,
    :state,
    :inserted_at,
    :updated_at
  ]
  defstruct @enforce_keys ++ [:revoked_at, :revocation_ref, metadata: %{}]

  @type state :: :active | :revoked
  @type t :: %__MODULE__{}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    account = struct(__MODULE__, attrs)

    with :ok <- validate_strings(account),
         :ok <- validate_counters(account),
         :ok <- validate_state(account.state) do
      {:ok, account}
    end
  rescue
    KeyError -> {:error, :invalid_managed_account}
    ArgumentError -> {:error, :invalid_managed_account}
  end

  def new(_attrs), do: {:error, :invalid_managed_account}

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, account} -> account
      {:error, reason} -> raise ArgumentError, "invalid managed account: #{inspect(reason)}"
    end
  end

  @spec ref(t()) :: ManagedAccountRef.t()
  def ref(%__MODULE__{} = account) do
    ManagedAccountRef.new!(%{
      provider_family: account.provider_family,
      account_ref: account.account_ref,
      tenant_id: account.tenant_id,
      connection_id: account.connection_id,
      endpoint_ref: account.endpoint_ref,
      quota_scope_ref: account.quota_scope_ref,
      generation: account.generation,
      fence: account.fence
    })
  end

  defp validate_strings(account) do
    fields = [
      :provider_family,
      :account_ref,
      :tenant_id,
      :connection_id,
      :endpoint_ref,
      :quota_scope_ref,
      :credential_handle_ref,
      :secret_provider_ref,
      :secret_binding_ref
    ]

    if Enum.all?(fields, &present_string?(Map.fetch!(account, &1))),
      do: :ok,
      else: {:error, :invalid_managed_account}
  end

  defp validate_counters(%__MODULE__{generation: generation, fence: fence})
       when is_integer(generation) and generation > 0 and is_integer(fence) and fence >= 0,
       do: :ok

  defp validate_counters(_account), do: {:error, :invalid_managed_account}
  defp validate_state(state) when state in [:active, :revoked], do: :ok
  defp validate_state(_state), do: {:error, :invalid_managed_account}
  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
end

defmodule Jido.Integration.V2.Auth.ManagedCredentialVersion do
  @moduledoc "Durable secret-handle generation for a managed provider account."

  @enforce_keys [
    :account_ref,
    :generation,
    :credential_handle_ref,
    :secret_provider_ref,
    :secret_binding_ref,
    :inserted_at
  ]
  defstruct @enforce_keys ++ [:supersedes_generation, :revoked_at, metadata: %{}]

  @type t :: %__MODULE__{}
end
