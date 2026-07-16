defmodule Jido.Integration.V2.StorePostgres.ManagedAccountStore do
  @moduledoc "Postgres owner store for managed provider accounts and credential generations."

  @behaviour Jido.Integration.V2.Auth.ManagedAccountStore

  import Ecto.Query

  alias Jido.Integration.V2.Auth.ManagedAccount
  alias Jido.Integration.V2.Auth.ManagedCredentialVersion
  alias Jido.Integration.V2.Auth.SecretGuard
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.ManagedAccountRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.ManagedCredentialVersionRecord
  alias Jido.Integration.V2.StorePostgres.Serialization

  @impl true
  def transact(fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      case fun.() do
        {:error, reason} -> Repo.rollback(reason)
        result -> result
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def register(%ManagedAccount{} = account, %ManagedCredentialVersion{} = version) do
    with :ok <- SecretGuard.validate_durable(account),
         :ok <- SecretGuard.validate_durable(version) do
      Repo.transaction(fn ->
        with {:ok, _account} <-
               account
               |> account_attrs()
               |> then(&ManagedAccountRecord.changeset(%ManagedAccountRecord{}, &1))
               |> Repo.insert(),
             {:ok, _version} <- insert_version(version) do
          :ok
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
      |> normalize_transaction()
    end
  end

  @impl true
  def fetch(account_ref) when is_binary(account_ref) do
    case Repo.get(ManagedAccountRecord, account_ref) do
      nil -> {:error, :unknown_managed_account}
      record -> {:ok, to_account(record)}
    end
  end

  @impl true
  def lock(account_ref) when is_binary(account_ref) do
    case Repo.one(
           from(account in ManagedAccountRecord,
             where: account.account_ref == ^account_ref,
             lock: "FOR UPDATE"
           )
         ) do
      nil -> {:error, :unknown_managed_account}
      record -> {:ok, to_account(record)}
    end
  end

  @impl true
  def fetch_by_connection(connection_id) when is_binary(connection_id) do
    case Repo.get_by(ManagedAccountRecord, connection_id: connection_id) do
      nil -> {:error, :unknown_managed_account}
      record -> {:ok, to_account(record)}
    end
  end

  @impl true
  def fetch_version(account_ref, generation)
      when is_binary(account_ref) and is_integer(generation) and generation > 0 do
    case Repo.get_by(ManagedCredentialVersionRecord,
           account_ref: account_ref,
           generation: generation
         ) do
      nil -> {:error, :unknown_credential_generation}
      record -> {:ok, to_version(record)}
    end
  end

  @impl true
  def rotate(
        account_ref,
        expected_generation,
        next_fence,
        %ManagedCredentialVersion{} = version,
        now
      ) do
    with :ok <- SecretGuard.validate_durable(version) do
      Repo.transaction(fn ->
        account = lock_account!(account_ref)

        cond do
          account.state != :active ->
            Repo.rollback(:managed_account_revoked)

          account.generation != expected_generation ->
            Repo.rollback(:stale_managed_account_generation)

          next_fence <= account.fence ->
            Repo.rollback(:stale_fence)

          true ->
            previous =
              Repo.get_by!(ManagedCredentialVersionRecord,
                account_ref: account_ref,
                generation: expected_generation
              )

            with {:ok, _previous} <-
                   previous
                   |> ManagedCredentialVersionRecord.changeset(%{superseded_at: now})
                   |> Repo.update(),
                 {:ok, _version} <- insert_version(version),
                 {:ok, updated} <-
                   account
                   |> ManagedAccountRecord.changeset(%{
                     generation: version.generation,
                     fence: next_fence,
                     credential_handle_ref: version.credential_handle_ref,
                     secret_provider_ref: version.secret_provider_ref,
                     secret_binding_ref: version.secret_binding_ref,
                     updated_at: now
                   })
                   |> Repo.update() do
              to_account(updated)
            else
              {:error, changeset} -> Repo.rollback(changeset)
            end
        end
      end)
      |> normalize_transaction()
    end
  end

  @impl true
  def revoke(account_ref, expected_generation, expected_fence, revocation_ref, now)
      when is_binary(account_ref) and is_integer(expected_generation) and
             is_integer(expected_fence) and is_binary(revocation_ref) do
    Repo.transaction(fn ->
      account = lock_account!(account_ref)

      cond do
        account.generation != expected_generation or account.fence != expected_fence ->
          Repo.rollback(:stale_managed_account_ref)

        account.state == :revoked ->
          to_account(account)

        true ->
          current =
            Repo.get_by!(ManagedCredentialVersionRecord,
              account_ref: account_ref,
              generation: account.generation
            )

          with {:ok, _current} <-
                 current
                 |> ManagedCredentialVersionRecord.changeset(%{revoked_at: now})
                 |> Repo.update(),
               {:ok, revoked} <-
                 account
                 |> ManagedAccountRecord.changeset(%{
                   state: :revoked,
                   revoked_at: now,
                   revocation_ref: revocation_ref,
                   updated_at: now
                 })
                 |> Repo.update() do
            to_account(revoked)
          else
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
    |> normalize_transaction()
  end

  def reset! do
    StorePostgres.assert_started!()
    Repo.delete_all(ManagedCredentialVersionRecord)
    Repo.delete_all(ManagedAccountRecord)
    :ok
  end

  defp lock_account!(account_ref) do
    case Repo.one(
           from(account in ManagedAccountRecord,
             where: account.account_ref == ^account_ref,
             lock: "FOR UPDATE"
           )
         ) do
      nil -> Repo.rollback(:unknown_managed_account)
      account -> account
    end
  end

  defp insert_version(version) do
    version
    |> version_attrs()
    |> then(&ManagedCredentialVersionRecord.changeset(%ManagedCredentialVersionRecord{}, &1))
    |> Repo.insert()
  end

  defp account_attrs(account) do
    account
    |> Map.from_struct()
    |> Map.update!(:metadata, &Serialization.dump/1)
  end

  defp version_attrs(version) do
    version
    |> Map.from_struct()
    |> Map.update!(:metadata, &Serialization.dump/1)
  end

  defp to_account(record) do
    ManagedAccount.new!(%{
      provider_family: record.provider_family,
      account_ref: record.account_ref,
      tenant_id: record.tenant_id,
      connection_id: record.connection_id,
      endpoint_ref: record.endpoint_ref,
      quota_scope_ref: record.quota_scope_ref,
      generation: record.generation,
      fence: record.fence,
      credential_handle_ref: record.credential_handle_ref,
      secret_provider_ref: record.secret_provider_ref,
      secret_binding_ref: record.secret_binding_ref,
      state: record.state,
      revoked_at: record.revoked_at,
      revocation_ref: record.revocation_ref,
      inserted_at: record.inserted_at,
      updated_at: record.updated_at,
      metadata: Serialization.load(record.metadata || %{})
    })
  end

  defp to_version(record) do
    struct!(ManagedCredentialVersion, %{
      account_ref: record.account_ref,
      generation: record.generation,
      credential_handle_ref: record.credential_handle_ref,
      secret_provider_ref: record.secret_provider_ref,
      secret_binding_ref: record.secret_binding_ref,
      supersedes_generation: record.supersedes_generation,
      revoked_at: record.revoked_at,
      inserted_at: record.inserted_at,
      metadata: Serialization.load(record.metadata || %{})
    })
  end

  defp normalize_transaction({:ok, :ok}), do: :ok
  defp normalize_transaction({:ok, result}), do: {:ok, result}
  defp normalize_transaction({:error, reason}), do: {:error, reason}
end
