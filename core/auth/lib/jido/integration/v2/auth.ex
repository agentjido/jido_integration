defmodule Jido.Integration.V2.Auth do
  @moduledoc """
  Durable connection/install truth plus short-lived credential leases.
  """

  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.Auth.LeaseRecord
  alias Jido.Integration.V2.Auth.Store
  alias Jido.Integration.V2.Auth.Stores
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef

  @default_install_ttl_seconds 600
  @default_lease_ttl_seconds 300

  @type refresh_handler ::
          (Connection.t(), Credential.t() ->
             {:ok, %{optional(:secret) => map(), optional(:expires_at) => DateTime.t() | nil}}
             | {:error, term()})

  @type connection_binding :: %{
          connection: Connection.t(),
          credential_ref: CredentialRef.t(),
          credential: Credential.t()
        }

  @spec start_install(String.t(), String.t(), map()) ::
          {:ok, %{install: Install.t(), connection: Connection.t(), session_state: map()}}
          | {:error, term()}
  def start_install(connector_id, tenant_id, opts \\ %{}) when is_binary(connector_id) do
    opts = Map.new(opts)
    now = now(opts)
    actor_id = Map.fetch!(opts, :actor_id)
    auth_type = Map.fetch!(opts, :auth_type)
    subject = Map.fetch!(opts, :subject)
    requested_scopes = Map.get(opts, :requested_scopes, [])
    metadata = Map.get(opts, :metadata, %{})

    with {:ok, connection} <-
           install_connection_for_start(connector_id, tenant_id, auth_type, subject, opts, now) do
      install =
        Install.new!(%{
          install_id: Contracts.next_id("install"),
          connection_id: connection.connection_id,
          tenant_id: tenant_id,
          connector_id: connector_id,
          actor_id: actor_id,
          auth_type: auth_type,
          subject: subject,
          state: :installing,
          callback_token: Contracts.next_id("install_callback"),
          requested_scopes: requested_scopes,
          granted_scopes: [],
          expires_at:
            DateTime.add(
              now,
              Map.get(opts, :install_ttl_seconds, @default_install_ttl_seconds),
              :second
            ),
          metadata: metadata,
          inserted_at: now,
          updated_at: now
        })

      :ok = Stores.install_store().store_install(install)

      {:ok,
       %{
         install: install,
         connection: connection,
         session_state: %{install_id: install.install_id, callback_token: install.callback_token}
       }}
    end
  end

  @spec complete_install(String.t(), map()) ::
          {:ok,
           %{install: Install.t(), connection: Connection.t(), credential_ref: CredentialRef.t()}}
          | {:error, term()}
  def complete_install(install_id, attrs) do
    attrs = Map.new(attrs)
    now = now(attrs)

    with {:ok, install} <- fetch_install(install_id),
         :ok <- ensure_install_open(install, now),
         {:ok, connection} <- Stores.connection_store().fetch_connection(install.connection_id),
         :ok <-
           ensure_subject_match(
             install.subject,
             Map.fetch!(attrs, :subject),
             :install_subject_mismatch
           ),
         {:ok, next_connection} <- transition_connection(connection, :connected),
         credential <- build_credential(next_connection, attrs),
         credential_ref <- build_credential_ref(credential, next_connection, install),
         completed_install <- complete_install_record(install, attrs, now),
         connected_connection <-
           %Connection{
             next_connection
             | credential_ref_id: credential_ref.id,
               install_id: install.install_id,
               granted_scopes: credential.scopes,
               lease_fields: credential.lease_fields,
               token_expires_at: credential.expires_at,
               revoked_at: nil,
               revocation_reason: nil,
               actor_id: Map.get(attrs, :actor_id, install.actor_id),
               updated_at: now
           },
         :ok <- Stores.credential_store().store_credential(credential),
         :ok <- Stores.install_store().store_install(completed_install),
         :ok <- Stores.connection_store().store_connection(connected_connection) do
      {:ok,
       %{
         install: completed_install,
         connection: connected_connection,
         credential_ref: credential_ref
       }}
    end
  end

  @spec fetch_install(String.t()) :: {:ok, Install.t()} | {:error, :unknown_install}
  def fetch_install(install_id), do: Stores.install_store().fetch_install(install_id)

  @spec installs(map()) :: [Install.t()]
  def installs(filters \\ %{}) when is_map(filters) do
    Stores.install_store().list_installs(filters)
  end

  @spec connection_status(String.t()) :: {:ok, Connection.t()} | {:error, :unknown_connection}
  def connection_status(connection_id),
    do: Stores.connection_store().fetch_connection(connection_id)

  @spec connections(map()) :: [Connection.t()]
  def connections(filters \\ %{}) when is_map(filters) do
    Stores.connection_store().list_connections(filters)
  end

  @spec request_lease(String.t(), map()) ::
          {:ok, CredentialLease.t()}
          | {:error,
             :unknown_connection
             | :unknown_credential
             | :credential_expired
             | :connection_installing
             | :connection_disabled
             | :connection_revoked
             | :reauth_required
             | :expired_lease
             | {:missing_connection_scopes, [String.t()]}}
  def request_lease(connection_id, context \\ %{}) do
    context = Map.new(context)
    now = now(context)

    with {:ok, connection} <- Stores.connection_store().fetch_connection(connection_id),
         :ok <- ensure_connection_available(connection),
         {:ok, credential} <- fetch_durable_credential(connection.credential_ref_id),
         :ok <-
           ensure_subject_match(
             connection.subject,
             credential.subject,
             :credential_subject_mismatch
           ),
         {:ok, refreshed_connection, refreshed_credential} <-
           maybe_refresh(connection, credential, now),
         :ok <- validate_required_scopes(refreshed_connection, context) do
      requested_scopes = requested_scopes(refreshed_connection, context)
      payload_keys = payload_keys(refreshed_connection, refreshed_credential, context)
      ttl_seconds = Map.get(context, :ttl_seconds, @default_lease_ttl_seconds)

      lease_record =
        LeaseRecord.new!(%{
          lease_id: Contracts.next_id("lease"),
          credential_ref_id: refreshed_credential.id,
          connection_id: refreshed_connection.connection_id,
          subject: refreshed_credential.subject,
          scopes: requested_scopes,
          payload_keys: payload_keys,
          issued_at: now,
          expires_at: DateTime.add(now, ttl_seconds, :second),
          metadata: %{
            actor_id: Map.get(context, :actor_id),
            connection_id: refreshed_connection.connection_id
          }
        })

      :ok = Stores.lease_store().store_lease(lease_record)
      {:ok, materialize_lease(lease_record, refreshed_credential)}
    end
  end

  @spec resolve_connection_binding(String.t(), map()) ::
          {:ok, connection_binding()}
          | {:error,
             :unknown_connection
             | :unknown_credential
             | :credential_subject_mismatch
             | :credential_expired
             | :connection_installing
             | :connection_disabled
             | :connection_revoked
             | :reauth_required}
  def resolve_connection_binding(connection_id, context \\ %{}) when is_binary(connection_id) do
    context = Map.new(context)
    now = now(context)

    with {:ok, connection} <- Stores.connection_store().fetch_connection(connection_id),
         :ok <- ensure_connection_available(connection),
         {:ok, credential} <- fetch_durable_credential(connection.credential_ref_id),
         :ok <-
           ensure_subject_match(
             connection.subject,
             credential.subject,
             :credential_subject_mismatch
           ),
         {:ok, refreshed_connection, refreshed_credential} <-
           maybe_refresh(connection, credential, now),
         credential_ref <- build_credential_ref(refreshed_credential, refreshed_connection, nil) do
      {:ok,
       %{
         connection: refreshed_connection,
         credential_ref: credential_ref,
         credential: Credential.sanitized(refreshed_credential)
       }}
    end
  end

  @spec issue_lease(CredentialRef.t(), map()) ::
          {:ok, CredentialLease.t()}
          | {:error,
             :unknown_connection
             | :unknown_credential
             | :credential_subject_mismatch
             | :credential_expired
             | :connection_installing
             | :connection_disabled
             | :connection_revoked
             | :reauth_required
             | {:missing_connection_scopes, [String.t()]}}
  def issue_lease(%CredentialRef{} = credential_ref, context \\ %{}) when is_map(context) do
    with {:ok, credential} <- fetch_durable_credential(credential_ref.id),
         :ok <- match_subject(credential_ref, credential),
         connection_id when is_binary(connection_id) <- connection_id(credential_ref, credential) do
      request_lease(connection_id, context)
    else
      nil -> {:error, :unknown_connection}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_lease(String.t(), map()) ::
          {:ok, CredentialLease.t()}
          | {:error,
             :unknown_lease
             | :expired_lease
             | :unknown_credential
             | :connection_revoked
             | :reauth_required}
  def fetch_lease(lease_id, context \\ %{}) do
    context = Map.new(context)
    now = now(context)

    with {:ok, lease_record} <- Stores.lease_store().fetch_lease(lease_id),
         :ok <- ensure_lease_active(lease_record, now),
         {:ok, connection} <-
           Stores.connection_store().fetch_connection(lease_record.connection_id),
         :ok <- ensure_connection_available(connection),
         {:ok, credential} <- fetch_durable_credential(lease_record.credential_ref_id),
         :ok <-
           ensure_subject_match(
             lease_record.subject,
             credential.subject,
             :credential_subject_mismatch
           ) do
      {:ok, materialize_lease(lease_record, credential)}
    end
  end

  @spec resolve(CredentialRef.t(), map()) ::
          {:ok, Credential.t()} | {:error, :unknown_credential | :credential_subject_mismatch}
  def resolve(%CredentialRef{} = credential_ref, _context \\ %{}) do
    with {:ok, credential} <- fetch_durable_credential(credential_ref.id),
         :ok <- match_subject(credential_ref, credential) do
      {:ok, Credential.sanitized(credential)}
    end
  end

  @spec resolve_secret(CredentialRef.t(), String.t() | atom()) ::
          {:ok, term()}
          | {:error, :unknown_credential | :credential_subject_mismatch | :unknown_secret}
  def resolve_secret(%CredentialRef{} = credential_ref, secret_key) do
    with {:ok, credential} <- fetch_durable_credential(credential_ref.id),
         :ok <- match_subject(credential_ref, credential) do
      fetch_secret_value(credential, secret_key)
    end
  end

  @spec rotate_connection(String.t(), map()) ::
          {:ok, %{connection: Connection.t(), credential_ref: CredentialRef.t()}}
          | {:error, term()}
  def rotate_connection(connection_id, attrs) do
    attrs = Map.new(attrs)
    now = now(attrs)

    with {:ok, connection} <- Stores.connection_store().fetch_connection(connection_id),
         {:ok, credential} <- fetch_durable_credential(connection.credential_ref_id),
         {:ok, next_connection} <- transition_connection(connection, :connected),
         rotated_credential <- build_rotated_credential(credential, next_connection, attrs),
         credential_ref <- build_credential_ref(rotated_credential, next_connection, nil),
         rotated_connection <-
           %Connection{
             next_connection
             | credential_ref_id: credential_ref.id,
               granted_scopes: rotated_credential.scopes,
               lease_fields: rotated_credential.lease_fields,
               token_expires_at: rotated_credential.expires_at,
               last_rotated_at: now,
               revoked_at: nil,
               revocation_reason: nil,
               actor_id: Map.get(attrs, :actor_id),
               updated_at: now
           },
         :ok <- Stores.credential_store().store_credential(rotated_credential),
         :ok <- Stores.connection_store().store_connection(rotated_connection) do
      {:ok, %{connection: rotated_connection, credential_ref: credential_ref}}
    end
  end

  @spec revoke_connection(String.t(), map()) :: {:ok, Connection.t()} | {:error, term()}
  def revoke_connection(connection_id, attrs) do
    attrs = Map.new(attrs)
    now = now(attrs)

    with {:ok, connection} <- Stores.connection_store().fetch_connection(connection_id),
         {:ok, next_connection} <- transition_connection(connection, :revoked),
         {:ok, credential} <- fetch_durable_credential(connection.credential_ref_id) do
      revoked_connection =
        %Connection{
          next_connection
          | state: :revoked,
            revoked_at: now,
            revocation_reason: Map.get(attrs, :reason),
            actor_id: Map.get(attrs, :actor_id),
            updated_at: now
        }

      revoked_credential =
        %Credential{credential | secret: %{}, revoked_at: now, expires_at: nil}

      :ok = Stores.connection_store().store_connection(revoked_connection)
      :ok = Stores.credential_store().store_credential(revoked_credential)
      {:ok, revoked_connection}
    end
  end

  @spec set_refresh_handler(refresh_handler() | nil) :: :ok
  def set_refresh_handler(handler) when is_function(handler, 2) or is_nil(handler) do
    Store.set_refresh_handler(handler)
    :ok
  end

  @spec reset!() :: :ok
  def reset! do
    Store.set_refresh_handler(nil)
    reset_store(Stores.install_store())
    reset_store(Stores.connection_store())
    reset_store(Stores.lease_store())
    reset_store(Stores.credential_store())
  end

  defp install_connection_for_start(connector_id, tenant_id, auth_type, subject, opts, now) do
    case Map.get(opts, :connection_id) do
      nil ->
        connection =
          Connection.new!(%{
            connection_id: Contracts.next_id("connection"),
            tenant_id: tenant_id,
            connector_id: connector_id,
            auth_type: auth_type,
            subject: subject,
            state: :installing,
            requested_scopes: Map.get(opts, :requested_scopes, []),
            granted_scopes: [],
            actor_id: Map.get(opts, :actor_id),
            metadata: Map.get(opts, :metadata, %{}),
            inserted_at: now,
            updated_at: now
          })

        :ok = Stores.connection_store().store_connection(connection)
        {:ok, connection}

      connection_id ->
        with {:ok, connection} <- Stores.connection_store().fetch_connection(connection_id),
             :ok <-
               ensure_subject_match(connection.subject, subject, :connection_subject_mismatch),
             {:ok, installing_connection} <- transition_connection(connection, :installing) do
          installing_connection =
            %Connection{
              installing_connection
              | requested_scopes: Map.get(opts, :requested_scopes, connection.requested_scopes),
                actor_id: Map.get(opts, :actor_id),
                updated_at: now
            }

          :ok = Stores.connection_store().store_connection(installing_connection)
          {:ok, installing_connection}
        end
    end
  end

  defp fetch_durable_credential(nil), do: {:error, :unknown_credential}

  defp fetch_durable_credential(credential_id),
    do: Stores.credential_store().fetch_credential(credential_id)

  defp build_credential(%Connection{} = connection, attrs) do
    Credential.new!(%{
      id: credential_id(connection.connection_id),
      connection_id: connection.connection_id,
      subject: connection.subject,
      auth_type: connection.auth_type,
      scopes: Map.get(attrs, :granted_scopes, connection.requested_scopes),
      secret: Map.get(attrs, :secret, %{}),
      lease_fields: Map.get(attrs, :lease_fields),
      expires_at: Map.get(attrs, :expires_at),
      metadata: Map.get(attrs, :metadata, %{})
    })
  end

  defp build_rotated_credential(%Credential{} = credential, %Connection{} = connection, attrs) do
    Credential.new!(%{
      id: credential.id,
      connection_id: connection.connection_id,
      subject: connection.subject,
      auth_type: connection.auth_type,
      scopes: Map.get(attrs, :granted_scopes, credential.scopes),
      secret: Map.fetch!(attrs, :secret),
      lease_fields: Map.get(attrs, :lease_fields, credential.lease_fields),
      expires_at: Map.get(attrs, :expires_at, credential.expires_at),
      metadata: Map.get(attrs, :metadata, credential.metadata)
    })
  end

  defp build_credential_ref(%Credential{} = credential, %Connection{} = connection, install) do
    CredentialRef.new!(%{
      id: credential.id,
      subject: credential.subject,
      scopes: credential.scopes,
      metadata: %{
        connection_id: connection.connection_id,
        install_id: install && install.install_id,
        connector_id: connection.connector_id,
        tenant_id: connection.tenant_id,
        auth_type: connection.auth_type
      }
    })
  end

  defp complete_install_record(%Install{} = install, attrs, now) do
    %Install{
      install
      | state: :completed,
        granted_scopes: Map.get(attrs, :granted_scopes, install.requested_scopes),
        completed_at: now,
        updated_at: now
    }
  end

  defp maybe_refresh(%Connection{} = connection, %Credential{} = credential, now) do
    if Credential.expired?(credential, now) do
      with true <- refreshable?(credential) or {:error, :credential_expired},
           handler when is_function(handler, 2) <-
             Store.refresh_handler() || {:error, :credential_expired},
           {:ok, refresh_result} <- handler.(connection, credential) do
        refreshed_credential =
          Credential.new!(%{
            id: credential.id,
            connection_id: credential.connection_id,
            subject: credential.subject,
            auth_type: credential.auth_type,
            scopes: Map.get(refresh_result, :scopes, credential.scopes),
            secret: Map.get(refresh_result, :secret, credential.secret),
            lease_fields: Map.get(refresh_result, :lease_fields, credential.lease_fields),
            expires_at: Map.get(refresh_result, :expires_at, credential.expires_at),
            metadata: Map.get(refresh_result, :metadata, credential.metadata)
          })

        refreshed_connection =
          %Connection{
            connection
            | state: :connected,
              granted_scopes: refreshed_credential.scopes,
              lease_fields: refreshed_credential.lease_fields,
              token_expires_at: refreshed_credential.expires_at,
              updated_at: now
          }

        :ok = Stores.credential_store().store_credential(refreshed_credential)
        :ok = Stores.connection_store().store_connection(refreshed_connection)
        {:ok, refreshed_connection, refreshed_credential}
      else
        {:error, _reason} ->
          mark_reauth_required(connection, now)
      end
    else
      {:ok, connection, credential}
    end
  end

  defp mark_reauth_required(%Connection{} = connection, now) do
    with {:ok, reauth_connection} <- transition_connection(connection, :reauth_required) do
      reauth_connection = %Connection{
        reauth_connection
        | state: :reauth_required,
          updated_at: now
      }

      :ok = Stores.connection_store().store_connection(reauth_connection)
      {:error, :reauth_required}
    end
  end

  defp materialize_lease(%LeaseRecord{} = lease_record, %Credential{} = credential) do
    CredentialLease.new!(%{
      lease_id: lease_record.lease_id,
      credential_ref_id: lease_record.credential_ref_id,
      subject: lease_record.subject,
      scopes: lease_record.scopes,
      payload: Credential.lease_payload(credential, lease_record.payload_keys),
      issued_at: lease_record.issued_at,
      expires_at: lease_record.expires_at,
      metadata: Map.merge(lease_record.metadata, %{connection_id: lease_record.connection_id})
    })
  end

  defp requested_scopes(%Connection{}, %{required_scopes: required_scopes})
       when is_list(required_scopes),
       do: required_scopes

  defp requested_scopes(%Connection{granted_scopes: granted_scopes}, _context), do: granted_scopes

  defp payload_keys(%Connection{} = connection, %Credential{} = credential, context) do
    case Map.get(context, :payload_keys) do
      nil ->
        if connection.lease_fields == [],
          do: credential.lease_fields,
          else: connection.lease_fields

      keys when is_list(keys) ->
        Enum.map(keys, &normalize_key/1)
    end
  end

  defp validate_required_scopes(%Connection{granted_scopes: granted_scopes}, %{
         required_scopes: required_scopes
       })
       when is_list(required_scopes) do
    case required_scopes -- granted_scopes do
      [] -> :ok
      missing -> {:error, {:missing_connection_scopes, missing}}
    end
  end

  defp validate_required_scopes(_connection, _context), do: :ok

  defp ensure_install_open(%Install{} = install, now) do
    cond do
      install.state != :installing ->
        {:error, :install_already_consumed}

      Install.expired?(install, now) ->
        {:error, :install_expired}

      true ->
        :ok
    end
  end

  defp ensure_connection_available(%Connection{state: :installing}),
    do: {:error, :connection_installing}

  defp ensure_connection_available(%Connection{state: :disabled}),
    do: {:error, :connection_disabled}

  defp ensure_connection_available(%Connection{state: :revoked}),
    do: {:error, :connection_revoked}

  defp ensure_connection_available(%Connection{state: :reauth_required}),
    do: {:error, :reauth_required}

  defp ensure_connection_available(%Connection{}), do: :ok

  defp ensure_lease_active(%LeaseRecord{revoked_at: %DateTime{}}, _now),
    do: {:error, :expired_lease}

  defp ensure_lease_active(%LeaseRecord{} = lease_record, now) do
    if DateTime.compare(lease_record.expires_at, now) == :gt,
      do: :ok,
      else: {:error, :expired_lease}
  end

  defp ensure_subject_match(expected, actual, _reason) when expected == actual, do: :ok
  defp ensure_subject_match(_expected, _actual, reason), do: {:error, reason}

  defp match_subject(%CredentialRef{subject: subject}, %Credential{subject: subject}), do: :ok
  defp match_subject(_credential_ref, _credential), do: {:error, :credential_subject_mismatch}

  defp fetch_secret_value(%Credential{} = credential, secret_key) do
    normalized_secret_key = normalize_key(secret_key)

    case Enum.find(Map.keys(credential.secret), &(normalize_key(&1) == normalized_secret_key)) do
      nil -> {:error, :unknown_secret}
      key -> {:ok, Map.fetch!(credential.secret, key)}
    end
  end

  defp transition_connection(%Connection{} = connection, to_state) do
    cond do
      connection.state == to_state ->
        {:ok, connection}

      Connection.can_transition?(connection.state, to_state) ->
        {:ok, %Connection{connection | state: to_state}}

      true ->
        {:error, {:invalid_connection_transition, connection.state, to_state}}
    end
  end

  defp refreshable?(%Credential{} = credential) do
    credential.secret
    |> Map.keys()
    |> Enum.any?(&(normalize_key(&1) == "refresh_token"))
  end

  defp connection_id(%CredentialRef{} = credential_ref, %Credential{} = credential) do
    metadata = Map.get(credential_ref, :metadata, %{})

    Map.get(
      metadata,
      :connection_id,
      Map.get(metadata, "connection_id", credential.connection_id)
    )
  end

  defp credential_id(connection_id), do: "cred:" <> connection_id

  defp now(map), do: Map.get(map, :now, Contracts.now())

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key

  defp reset_store(module) do
    if function_exported?(module, :reset!, 0) do
      module.reset!()
    end
  end
end
