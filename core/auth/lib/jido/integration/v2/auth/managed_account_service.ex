defmodule Jido.Integration.V2.Auth.ManagedAccountService do
  @moduledoc """
  Secret-free managed account lifecycle and bounded materialization entry point.

  Durable account identity and credential generations live in the configured
  managed-account store. Secret material is created and destroyed inside a
  short-lived task supervised by Auth and is never returned by this module.
  """

  alias Jido.Integration.V2.Auth.ManagedAccount
  alias Jido.Integration.V2.Auth.ManagedCredentialVersion
  alias Jido.Integration.V2.Auth.RuntimeConfig
  alias Jido.Integration.V2.Auth.SecretGuard
  alias Jido.Integration.V2.Auth.ServiceCore
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.ManagedAccountRef
  alias Jido.Integration.V2.MaterializationRequest
  alias Jido.Integration.V2.SecretMaterial

  @supervisor Jido.Integration.V2.Auth.MaterializationSupervisor

  @spec configure!(keyword() | map()) :: :ok
  def configure!(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)
    store = Map.fetch!(attrs, :store)
    materializers = Map.get(attrs, :materializers, %{}) |> Map.new()

    unless valid_store?(store) do
      raise ArgumentError, "invalid managed account store #{inspect(store)}"
    end

    Enum.each(materializers, fn {family, materializer} ->
      unless present_string?(family) and valid_materializer?(materializer) do
        raise ArgumentError,
              "invalid credential materializer #{inspect({family, materializer})}"
      end
    end)

    :ok = put_runtime(:managed_account_store, store)
    :ok = put_runtime(:credential_materializers, materializers)
  end

  @spec register(map() | keyword()) ::
          {:ok, %{account: ManagedAccount.t(), account_ref: ManagedAccountRef.t()}}
          | {:error, term()}
  def register(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)
    now = Map.get(attrs, :now, Contracts.now())

    with :ok <- SecretGuard.validate_durable(attrs),
         {:ok, store} <- store(),
         {:ok, fields} <- registration_fields(attrs) do
      store.transact(fn ->
        with {:ok, install_result} <- start_managed_install(fields, attrs, now),
             {:ok, completion} <-
               complete_managed_install(install_result.install, fields, attrs, now),
             account <- build_account(completion.connection, fields, now),
             version <- build_version(account, fields, nil, now),
             :ok <- store.register(account, version) do
          {:ok, %{account: account, account_ref: ManagedAccount.ref(account)}}
        end
      end)
    end
  end

  @spec fetch(ManagedAccountRef.t() | String.t()) ::
          {:ok, ManagedAccount.t()} | {:error, term()}
  def fetch(%ManagedAccountRef{} = expected) do
    with {:ok, account} <- fetch(expected.account_ref),
         true <- ManagedAccount.ref(account) == expected or {:error, :stale_managed_account_ref} do
      {:ok, account}
    end
  end

  def fetch(account_ref) when is_binary(account_ref) do
    with {:ok, store} <- store(), do: store.fetch(account_ref)
  end

  @spec current_credential_version(ManagedAccountRef.t() | String.t()) ::
          {:ok, ManagedCredentialVersion.t()} | {:error, term()}
  def current_credential_version(account_or_ref) do
    with {:ok, account} <- fetch(account_or_ref),
         {:ok, store} <- store() do
      store.fetch_version(account.account_ref, account.generation)
    end
  end

  @spec rotate(ManagedAccountRef.t(), map() | keyword()) ::
          {:ok, %{account: ManagedAccount.t(), account_ref: ManagedAccountRef.t()}}
          | {:error, term()}
  def rotate(%ManagedAccountRef{} = expected, attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    now = Map.get(attrs, :now, Contracts.now())

    with :ok <- SecretGuard.validate_durable(attrs),
         {:ok, account} <- fetch(expected),
         :ok <- ensure_active(account),
         {:ok, store} <- store(),
         next_generation = account.generation + 1,
         next_fence <- Map.get(attrs, :fence, account.fence + 1),
         true <- (is_integer(next_fence) and next_fence > account.fence) or {:error, :stale_fence},
         {:ok, credential_handle_ref} <-
           optional_string(attrs, :credential_handle_ref, account.credential_handle_ref),
         {:ok, secret_provider_ref} <-
           optional_string(attrs, :secret_provider_ref, account.secret_provider_ref),
         {:ok, secret_binding_ref} <- required_string(attrs, :secret_binding_ref),
         fields <- %{
           credential_handle_ref: credential_handle_ref,
           secret_provider_ref: secret_provider_ref,
           secret_binding_ref: secret_binding_ref
         },
         :ok <- SecretGuard.validate_durable(fields),
         version <- build_version(account, fields, account.generation, now, next_generation),
         {:ok, rotated} <-
           store.rotate(account.account_ref, account.generation, next_fence, version, now) do
      {:ok, %{account: rotated, account_ref: ManagedAccount.ref(rotated)}}
    end
  end

  @spec revoke(ManagedAccountRef.t(), map() | keyword()) ::
          {:ok, ManagedAccount.t()} | {:error, term()}
  def revoke(%ManagedAccountRef{} = expected, attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    now = Map.get(attrs, :now, Contracts.now())

    with :ok <- SecretGuard.validate_durable(attrs),
         {:ok, revocation_ref} <- required_string(attrs, :revocation_ref),
         {:ok, store} <- store() do
      store.transact(fn ->
        with {:ok, revoked} <-
               store.revoke(
                 expected.account_ref,
                 expected.generation,
                 expected.fence,
                 revocation_ref,
                 now
               ),
             {:ok, _connection} <-
               ServiceCore.revoke_connection(revoked.connection_id, %{
                 now: now,
                 reason: revocation_ref
               }) do
          {:ok, revoked}
        end
      end)
    end
  end

  @spec request_lease(ManagedAccountRef.t(), map()) ::
          {:ok, CredentialLease.t()} | {:error, term()}
  def request_lease(%ManagedAccountRef{} = expected, context) when is_map(context) do
    with :ok <- SecretGuard.validate_durable(context),
         {:ok, store} <- store() do
      store.transact(fn ->
        with {:ok, account} <- lock_expected_account(store, expected),
             :ok <- ensure_active(account),
             :ok <- reject_identity_substitution(account, context) do
          context =
            context
            |> Map.merge(%{
              tenant_id: account.tenant_id,
              authority_mode: :governed,
              execution_context_scope: :governed,
              provider_family: account.provider_family,
              provider_account_ref: account.account_ref,
              credential_handle_ref: account.credential_handle_ref,
              endpoint_ref: account.endpoint_ref,
              rotation_epoch: account.generation,
              fence_token: fence_token(account),
              managed_account_ref: ManagedAccount.ref(account),
              materialization_only?: true
            })

          ServiceCore.request_managed_lease(account, context)
        end
      end)
    end
  end

  @spec with_materialized(
          CredentialLease.t(),
          MaterializationRequest.t(),
          map(),
          (SecretMaterial.t() -> term())
        ) :: {:ok, term()} | {:error, term()}
  def with_materialized(
        %CredentialLease{} = lease,
        %MaterializationRequest{} = request,
        redemption_context,
        fun
      )
      when is_map(redemption_context) and is_function(fun, 1) do
    with :ok <- SecretGuard.validate_durable(redemption_context) do
      task =
        Task.Supervisor.async_nolink(@supervisor, fn ->
          do_with_materialized(lease, request, redemption_context, fun)
        end)

      case Task.yield(task, materialization_timeout(request)) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        {:exit, _reason} -> {:error, :materialization_process_failed}
        nil -> {:error, :materialization_deadline_exceeded}
      end
    end
  end

  defp do_with_materialized(lease, request, redemption_context, fun) do
    now = Map.get(redemption_context, :now, Contracts.now())

    with {:ok, account} <- admit_materialization(lease, request, redemption_context, now),
         {:ok, materializer} <- materializer(account.provider_family),
         {:ok, %SecretMaterial{} = material} <- materializer.materialize(lease, request) do
      try do
        with :ok <- ensure_material_alignment(material, account, request) do
          result = fun.(material)

          cond do
            SecretGuard.contains_material?(result, material.payload) ->
              {:error, :secret_material_leak}

            match?({:error, _reason}, SecretGuard.validate_durable(result)) ->
              {:error, :secret_material_leak}

            true ->
              {:ok, result}
          end
        end
      after
        _ = materializer.revoke(material, reason: :effect_scope_closed)
      end
    end
  end

  defp registration_fields(attrs) do
    keys = [
      :provider_family,
      :account_ref,
      :tenant_id,
      :connector_id,
      :endpoint_ref,
      :quota_scope_ref,
      :credential_handle_ref,
      :secret_provider_ref,
      :secret_binding_ref,
      :subject,
      :actor_id
    ]

    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, acc} ->
      case required_string(attrs, key) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp start_managed_install(fields, attrs, now) do
    ServiceCore.start_install(fields.connector_id, fields.tenant_id, %{
      actor_id: fields.actor_id,
      auth_type: Map.get(attrs, :auth_type, :api_key),
      subject: fields.subject,
      profile_id: Map.get(attrs, :profile_id, "default"),
      requested_scopes: Map.get(attrs, :scopes, []),
      management_mode: :jido_managed,
      secret_source: :external_ref,
      external_secret_ref: %{
        provider_ref: fields.secret_provider_ref,
        binding_ref: fields.secret_binding_ref
      },
      metadata: %{managed_account_ref: fields.account_ref},
      now: now
    })
  end

  defp complete_managed_install(install, fields, attrs, now) do
    ServiceCore.complete_install(install.install_id, %{
      subject: fields.subject,
      granted_scopes: Map.get(attrs, :scopes, []),
      secret: %{},
      lease_fields: Map.get(attrs, :lease_fields, []),
      source: :external_secret,
      source_ref: %{
        provider_ref: fields.secret_provider_ref,
        binding_ref: fields.secret_binding_ref,
        credential_handle_ref: fields.credential_handle_ref
      },
      management_mode: :jido_managed,
      secret_source: :external_ref,
      now: now
    })
  end

  defp build_account(connection, fields, now) do
    ManagedAccount.new!(%{
      provider_family: fields.provider_family,
      account_ref: fields.account_ref,
      tenant_id: fields.tenant_id,
      connection_id: connection.connection_id,
      endpoint_ref: fields.endpoint_ref,
      quota_scope_ref: fields.quota_scope_ref,
      generation: 1,
      fence: 0,
      credential_handle_ref: fields.credential_handle_ref,
      secret_provider_ref: fields.secret_provider_ref,
      secret_binding_ref: fields.secret_binding_ref,
      state: :active,
      inserted_at: now,
      updated_at: now,
      metadata: %{}
    })
  end

  defp build_version(account, fields, supersedes_generation, now, generation \\ 1) do
    struct!(ManagedCredentialVersion, %{
      account_ref: account.account_ref,
      generation: generation,
      credential_handle_ref: fields.credential_handle_ref,
      secret_provider_ref: fields.secret_provider_ref,
      secret_binding_ref: fields.secret_binding_ref,
      supersedes_generation: supersedes_generation,
      inserted_at: now,
      metadata: %{}
    })
  end

  defp reject_identity_substitution(account, context) do
    expected = %{
      tenant_id: account.tenant_id,
      provider_family: account.provider_family,
      provider_account_ref: account.account_ref,
      credential_handle_ref: account.credential_handle_ref,
      endpoint_ref: account.endpoint_ref,
      rotation_epoch: account.generation,
      fence_token: fence_token(account)
    }

    Enum.reduce_while(expected, :ok, fn {key, value}, :ok ->
      case Map.get(context, key, Map.get(context, Atom.to_string(key))) do
        nil -> {:cont, :ok}
        ^value -> {:cont, :ok}
        _other -> {:halt, {:error, {:managed_account_identity_mismatch, key}}}
      end
    end)
  end

  defp ensure_materialization_alignment(lease, request, account, now) do
    metadata = lease.metadata

    cond do
      request.lease_id != lease.lease_id ->
        {:error, :materialization_lease_mismatch}

      request.account != ManagedAccount.ref(account) ->
        {:error, :stale_managed_account_ref}

      lease.tenant_id != account.tenant_id ->
        {:error, :materialization_tenant_mismatch}

      lease.connection_id != account.connection_id ->
        {:error, :materialization_connection_mismatch}

      value(metadata, :provider_family) != account.provider_family ->
        {:error, :materialization_provider_mismatch}

      value(metadata, :provider_account_ref) != account.account_ref ->
        {:error, :materialization_account_mismatch}

      value(metadata, :credential_handle_ref) != account.credential_handle_ref ->
        {:error, :materialization_credential_mismatch}

      value(metadata, :rotation_epoch) != account.generation ->
        {:error, :materialization_generation_mismatch}

      value(metadata, :fence_token) != fence_token(account) ->
        {:error, :materialization_fence_mismatch}

      request.endpoint_ref != account.endpoint_ref ->
        {:error, :materialization_endpoint_mismatch}

      value(metadata, :endpoint_ref) != account.endpoint_ref ->
        {:error, :materialization_endpoint_mismatch}

      request.authority_ref != value(metadata, :authority_ref) ->
        {:error, :materialization_authority_mismatch}

      request.effect_ref != value(metadata, :effect_ref) ->
        {:error, :materialization_effect_mismatch}

      request.operation_ref != value(metadata, :operation_ref) ->
        {:error, :materialization_operation_mismatch}

      request.target_ref != value(metadata, :target_ref) ->
        {:error, :materialization_target_mismatch}

      DateTime.compare(request.issued_at, lease.issued_at) == :lt ->
        {:error, :materialization_outlives_lease}

      DateTime.compare(request.expires_at, lease.expires_at) == :gt ->
        {:error, :materialization_outlives_lease}

      DateTime.compare(request.issued_at, now) == :gt ->
        {:error, :materialization_not_yet_valid}

      not MaterializationRequest.valid_for?(request, ManagedAccount.ref(account), now) ->
        {:error, :expired_materialization_request}

      true ->
        :ok
    end
  end

  defp ensure_material_alignment(material, account, request) do
    if material.materialization_ref == request.materialization_ref and
         material.provider_family == account.provider_family and
         material.account_ref == account.account_ref and
         material.generation == account.generation do
      :ok
    else
      {:error, :secret_material_identity_mismatch}
    end
  end

  defp materializer(family) do
    case Map.get(RuntimeConfig.current().credential_materializers, family) do
      materializer when is_atom(materializer) -> {:ok, materializer}
      _missing -> {:error, {:credential_materializer_not_configured, family}}
    end
  end

  defp store do
    case RuntimeConfig.current().managed_account_store do
      store when is_atom(store) -> {:ok, store}
      _missing -> {:error, :managed_account_store_not_configured}
    end
  end

  defp record_materialization(lease_id, materialization_ref, now) do
    Jido.Integration.V2.Auth.Stores.lease_store().record_materialization(
      lease_id,
      materialization_ref,
      now
    )
  end

  defp admit_materialization(lease, request, redemption_context, now) do
    with {:ok, store} <- store() do
      store.transact(fn ->
        with {:ok, account} <- lock_expected_account(store, request.account),
             :ok <- ensure_active(account),
             :ok <- ensure_materialization_alignment(lease, request, account, now),
             {:ok, _evidence} <- ServiceCore.redeem_lease(lease.lease_id, redemption_context),
             {:ok, _record} <-
               record_materialization(lease.lease_id, request.materialization_ref, now) do
          {:ok, account}
        end
      end)
    end
  end

  defp lock_expected_account(store, %ManagedAccountRef{} = expected) do
    with {:ok, account} <- store.lock(expected.account_ref),
         true <- ManagedAccount.ref(account) == expected or {:error, :stale_managed_account_ref} do
      {:ok, account}
    end
  end

  defp ensure_active(%ManagedAccount{state: :active}), do: :ok
  defp ensure_active(%ManagedAccount{state: :revoked}), do: {:error, :managed_account_revoked}

  defp fence_token(account), do: "#{account.account_ref}:fence:#{account.fence}"

  defp materialization_timeout(request) do
    request.expires_at
    |> DateTime.diff(request.issued_at, :millisecond)
    |> max(1)
  end

  defp valid_store?(store) when is_atom(store) do
    Code.ensure_loaded?(store) and function_exported?(store, :transact, 1) and
      function_exported?(store, :fetch, 1) and
      function_exported?(store, :register, 2)
  end

  defp valid_store?(_store), do: false

  defp valid_materializer?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :materialize, 2) and
      function_exported?(module, :revoke, 2)
  end

  defp valid_materializer?(_module), do: false

  defp put_runtime(key, value) do
    case RuntimeConfig.put(key, value) do
      :ok -> :ok
      {:error, :not_started} -> raise ArgumentError, "auth runtime config is not started"
    end
  end

  defp required_string(attrs, key) do
    case Map.get(attrs, key, Map.get(attrs, Atom.to_string(key))) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:missing_managed_account_field, key}}
    end
  end

  defp optional_string(attrs, key, default) do
    case Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default)) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, {:invalid_managed_account_field, key}}
    end
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp present_string?(value), do: is_binary(value) and value != ""
end
