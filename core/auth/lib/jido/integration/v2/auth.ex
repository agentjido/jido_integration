defmodule Jido.Integration.V2.Auth do
  @moduledoc """
  Durable connection/install truth plus short-lived credential leases.
  """

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.Auth.LeaseRecord
  alias Jido.Integration.V2.Auth.Store
  alias Jido.Integration.V2.Auth.Supervisor, as: AuthSupervisor
  alias Jido.Integration.V2.Auth.Stores
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef

  @default_install_ttl_seconds 600
  @default_lease_ttl_seconds 300

  @type refresh_handler ::
          (Connection.t(), Credential.t() ->
             {:ok,
              %{
                optional(:secret) => map(),
                optional(:expires_at) => DateTime.t() | nil,
                optional(:refresh_token_expires_at) => DateTime.t() | nil,
                optional(:lease_fields) => [String.t()],
                optional(:metadata) => map(),
                optional(:source_ref) => map()
              }}
             | {:error, term()})

  @type external_secret_stage :: :lease | :fetch_lease | :refresh

  @type external_secret_opts :: %{
          stage: external_secret_stage(),
          requested_fields: [String.t()],
          missing_fields: [String.t()],
          now: DateTime.t()
        }

  @type external_secret_resolver ::
          (Connection.t(), Credential.t(), external_secret_opts() ->
             {:ok, map()} | {:error, term()})

  @type connection_binding :: %{
          connection: Connection.t(),
          credential_ref: CredentialRef.t(),
          credential: Credential.t()
        }

  @spec start_install(String.t(), String.t(), map()) ::
          {:ok, %{install: Install.t(), connection: Connection.t(), session_state: map()}}
          | {:error, term()}
  def start_install(connector_id, tenant_id, opts \\ %{}) when is_binary(connector_id) do
    opts =
      opts
      |> Map.new()
      |> enrich_install_opts()

    now = now(opts)
    actor_id = Map.fetch!(opts, :actor_id)
    auth_type = Map.fetch!(opts, :auth_type)
    profile_id = Map.get(opts, :profile_id, default_profile_id())
    flow_kind = Map.get(opts, :flow_kind, default_flow_kind(auth_type))
    subject = Map.fetch!(opts, :subject)
    requested_scopes = Map.get(opts, :requested_scopes, [])

    with {:ok, connection} <-
           install_connection_for_start(
             connector_id,
             tenant_id,
             auth_type,
             profile_id,
             flow_kind,
             subject,
             opts,
             now
           ) do
      metadata = install_metadata(connection, Map.get(opts, :metadata, %{}), opts)

      install =
        Install.new!(%{
          install_id: Contracts.next_id("install"),
          connection_id: connection.connection_id,
          tenant_id: tenant_id,
          connector_id: connector_id,
          actor_id: actor_id,
          auth_type: auth_type,
          profile_id: profile_id,
          subject: subject,
          state: :installing,
          flow_kind: flow_kind,
          callback_token: Contracts.next_id("install_callback"),
          state_token: Map.get(opts, :state_token),
          pkce_verifier_digest: Map.get(opts, :pkce_verifier_digest),
          callback_uri: Map.get(opts, :callback_uri, Contracts.get(metadata, :redirect_uri)),
          requested_scopes: requested_scopes,
          granted_scopes: [],
          expires_at:
            DateTime.add(
              now,
              Map.get(opts, :install_ttl_seconds, @default_install_ttl_seconds),
              :second
            ),
          reauth_of_connection_id: Map.get(opts, :connection_id),
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

  @spec resolve_install_callback(map()) ::
          {:ok, %{install: Install.t(), connection: Connection.t()}}
          | {:error,
             :callback_locator_required
             | :unknown_install
             | :ambiguous_install
             | :install_expired
             | :callback_already_consumed
             | :invalid_callback_state
             | :invalid_callback_token
             | :pkce_verifier_required
             | :invalid_pkce_verifier
             | {:callback_error, term()}
             | term()}
  def resolve_install_callback(attrs) when is_map(attrs) do
    attrs = Map.new(attrs)
    now = now(attrs)

    with {:ok, %Install{} = install} <- fetch_callback_install(attrs),
         :ok <- ensure_callback_pending(install, now),
         :ok <- validate_callback_token(install, attrs),
         :ok <- validate_callback_state(install, attrs),
         {:ok, connection} <- Stores.connection_store().fetch_connection(install.connection_id),
         :ok <- maybe_fail_callback(install, attrs, now),
         :ok <- validate_pkce_verifier(install, attrs) do
      callback_install =
        %Install{
          install
          | state: :awaiting_callback,
            callback_received_at: Contracts.get(attrs, :callback_received_at, now),
            callback_uri: Contracts.get(attrs, :callback_uri, install.callback_uri),
            updated_at: now
        }

      :ok = Stores.install_store().store_install(callback_install)
      {:ok, %{install: callback_install, connection: connection}}
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
         {:ok, %Connection{} = next_connection} <- transition_connection(connection, :connected),
         {:ok, previous_credential} <- fetch_current_credential(connection),
         credential_ref_id =
           connection.credential_ref_id || credential_ref_id(connection.connection_id),
         credential <-
           build_credential(
             next_connection,
             install,
             attrs,
             credential_ref_id,
             previous_credential
           ),
         credential_ref <-
           build_credential_ref(credential, next_connection, install, credential_ref_id),
         completed_install <- complete_install_record(install, attrs, now),
         connected_connection <-
           %Connection{
             next_connection
             | credential_ref_id: credential_ref.id,
               current_credential_ref_id: credential_ref.id,
               current_credential_id: credential.id,
               install_id: install.install_id,
               granted_scopes: credential.scopes,
               lease_fields: credential.lease_fields,
               token_expires_at: credential.expires_at,
               profile_id: credential.profile_id,
               management_mode:
                 Map.get(
                   attrs,
                   :management_mode,
                   connection.management_mode || default_management_mode(install.flow_kind)
                 ),
               secret_source:
                 Map.get(
                   attrs,
                   :secret_source,
                   connection.secret_source || default_secret_source(install.flow_kind)
                 ),
               last_refresh_at: nil,
               last_refresh_status: nil,
               degraded_reason: nil,
               reauth_required_reason: nil,
               disabled_reason: nil,
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

  @spec cancel_install(String.t(), map()) ::
          {:ok, %{install: Install.t(), connection: Connection.t()}} | {:error, term()}
  def cancel_install(install_id, attrs \\ %{}) when is_binary(install_id) and is_map(attrs) do
    terminalize_install(install_id, :cancelled, attrs)
  end

  @spec expire_install(String.t(), map()) ::
          {:ok, %{install: Install.t(), connection: Connection.t()}} | {:error, term()}
  def expire_install(install_id, attrs \\ %{}) when is_binary(install_id) and is_map(attrs) do
    terminalize_install(install_id, :expired, attrs)
  end

  @spec fail_install(String.t(), map()) ::
          {:ok, %{install: Install.t(), connection: Connection.t()}} | {:error, term()}
  def fail_install(install_id, attrs \\ %{}) when is_binary(install_id) and is_map(attrs) do
    terminalize_install(install_id, :failed, attrs)
  end

  @spec connection_status(String.t()) :: {:ok, Connection.t()} | {:error, :unknown_connection}
  def connection_status(connection_id),
    do: Stores.connection_store().fetch_connection(connection_id)

  @spec connections(map()) :: [Connection.t()]
  def connections(filters \\ %{}) when is_map(filters) do
    Stores.connection_store().list_connections(filters)
  end

  @spec reauthorize_connection(String.t(), map()) ::
          {:ok, %{install: Install.t(), connection: Connection.t(), session_state: map()}}
          | {:error, term()}
  def reauthorize_connection(connection_id, opts \\ %{})
      when is_binary(connection_id) and is_map(opts) do
    opts = Map.new(opts)

    with {:ok, connection} <- Stores.connection_store().fetch_connection(connection_id) do
      start_install(
        connection.connector_id,
        connection.tenant_id,
        opts
        |> Map.put(:connection_id, connection.connection_id)
        |> Map.put(:auth_type, connection.auth_type)
        |> Map.put(:profile_id, Map.get(opts, :profile_id, connection.profile_id))
        |> Map.put(:subject, connection.subject)
        |> Map.put(:flow_kind, Map.get(opts, :flow_kind, default_flow_kind(connection.auth_type)))
        |> Map.put(
          :requested_scopes,
          Map.get(opts, :requested_scopes, connection.requested_scopes)
        )
      )
    end
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
             | :external_secret_unavailable
             | :expired_lease
             | {:missing_connection_scopes, [String.t()]}
             | {:missing_lease_fields, [String.t()]}}
  def request_lease(connection_id, context \\ %{}) do
    context = Map.new(context)
    now = now(context)

    with {:ok, connection} <- Stores.connection_store().fetch_connection(connection_id),
         :ok <- ensure_connection_available(connection),
         {:ok, credential} <- fetch_active_credential(connection),
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

      with {:ok, lease_connection, payload} <-
             resolve_lease_payload(
               refreshed_connection,
               refreshed_credential,
               payload_keys,
               now,
               :lease
             ) do
        lease_record =
          LeaseRecord.new!(%{
            lease_id: Contracts.next_id("lease"),
            credential_ref_id: refreshed_credential.credential_ref_id,
            credential_id: refreshed_credential.id,
            connection_id: lease_connection.connection_id,
            profile_id: lease_connection.profile_id || refreshed_credential.profile_id,
            subject: refreshed_credential.subject,
            scopes: requested_scopes,
            payload_keys: payload_keys,
            issued_at: now,
            expires_at: DateTime.add(now, ttl_seconds, :second),
            metadata: %{
              actor_id: Map.get(context, :actor_id),
              connection_id: lease_connection.connection_id
            }
          })

        :ok = Stores.lease_store().store_lease(lease_record)
        {:ok, build_lease(lease_record, lease_connection, refreshed_credential, payload)}
      end
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
         {:ok, credential} <- fetch_active_credential(connection),
         :ok <-
           ensure_subject_match(
             connection.subject,
             credential.subject,
             :credential_subject_mismatch
           ),
         {:ok, refreshed_connection, refreshed_credential} <-
           maybe_refresh(connection, credential, now),
         credential_ref <-
           build_credential_ref(
             refreshed_credential,
             refreshed_connection,
             nil,
             refreshed_connection.credential_ref_id || refreshed_credential.credential_ref_id
           ) do
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
             | :external_secret_unavailable
             | {:missing_connection_scopes, [String.t()]}
             | {:missing_lease_fields, [String.t()]}}
  def issue_lease(%CredentialRef{} = credential_ref, context \\ %{}) when is_map(context) do
    with {:ok, credential} <- fetch_durable_credential(current_credential_id(credential_ref)),
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
             | :reauth_required
             | :external_secret_unavailable
             | {:missing_lease_fields, [String.t()]}}
  def fetch_lease(lease_id, context \\ %{}) do
    context = Map.new(context)
    now = now(context)

    with {:ok, lease_record} <- Stores.lease_store().fetch_lease(lease_id),
         :ok <- ensure_lease_active(lease_record, now),
         {:ok, connection} <-
           Stores.connection_store().fetch_connection(lease_record.connection_id),
         :ok <- ensure_connection_available(connection),
         {:ok, credential} <- fetch_durable_credential(lease_record.credential_id),
         :ok <-
           ensure_subject_match(
             lease_record.subject,
             credential.subject,
             :credential_subject_mismatch
           ),
         {:ok, lease_connection, payload} <-
           resolve_lease_payload(
             connection,
             credential,
             lease_record.payload_keys,
             now,
             :fetch_lease
           ) do
      {:ok, build_lease(lease_record, lease_connection, credential, payload)}
    end
  end

  @spec resolve(CredentialRef.t(), map()) ::
          {:ok, Credential.t()} | {:error, :unknown_credential | :credential_subject_mismatch}
  def resolve(%CredentialRef{} = credential_ref, _context \\ %{}) do
    with {:ok, credential} <- fetch_durable_credential(current_credential_id(credential_ref)),
         :ok <- match_subject(credential_ref, credential) do
      {:ok, Credential.sanitized(credential)}
    end
  end

  @spec resolve_secret(CredentialRef.t(), String.t() | atom()) ::
          {:ok, term()}
          | {:error, :unknown_credential | :credential_subject_mismatch | :unknown_secret}
  def resolve_secret(%CredentialRef{} = credential_ref, secret_key) do
    with {:ok, credential} <- fetch_durable_credential(current_credential_id(credential_ref)),
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
         {:ok, credential} <- fetch_active_credential(connection),
         {:ok, %Connection{} = next_connection} <- transition_connection(connection, :connected),
         rotated_credential <- build_rotated_credential(credential, next_connection, attrs),
         credential_ref <-
           build_credential_ref(
             rotated_credential,
             next_connection,
             nil,
             connection.credential_ref_id || credential.credential_ref_id
           ),
         rotated_connection <-
           %Connection{
             next_connection
             | credential_ref_id: credential_ref.id,
               current_credential_ref_id: credential_ref.id,
               current_credential_id: rotated_credential.id,
               granted_scopes: rotated_credential.scopes,
               lease_fields: rotated_credential.lease_fields,
               token_expires_at: rotated_credential.expires_at,
               last_rotated_at: now,
               secret_source:
                 Map.get(
                   attrs,
                   :secret_source,
                   connection.secret_source || default_secret_source(:manual)
                 ),
               degraded_reason: nil,
               reauth_required_reason: nil,
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
         {:ok, %Connection{} = next_connection} <- transition_connection(connection, :revoked),
         {:ok, %Credential{} = credential} <- fetch_active_credential(connection) do
      revoked_connection =
        %Connection{
          next_connection
          | state: :revoked,
            reauth_required_reason: nil,
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
    ensure_started!()
    Store.set_refresh_handler(handler)
    :ok
  end

  @spec set_external_secret_resolver(external_secret_resolver() | nil) :: :ok
  def set_external_secret_resolver(handler)
      when is_function(handler, 3) or is_nil(handler) do
    ensure_started!()
    Store.set_external_secret_resolver(handler)
    :ok
  end

  @spec reset!() :: :ok
  def reset! do
    ensure_started!()
    Store.set_refresh_handler(nil)
    Store.set_external_secret_resolver(nil)
    reset_store(Stores.install_store())
    reset_store(Stores.connection_store())
    reset_store(Stores.lease_store())
    reset_store(Stores.credential_store())
  end

  defp ensure_started! do
    case Process.whereis(Store) do
      nil ->
        ensure_store_started!()

      _pid ->
        :ok
    end
  end

  defp ensure_store_started! do
    case Process.whereis(AuthSupervisor) do
      nil ->
        case Jido.Integration.V2.Auth.Application.start(:normal, []) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> raise("auth application did not start: #{inspect(reason)}")
        end

      _pid ->
        case Supervisor.restart_child(AuthSupervisor, Store) do
          {:ok, _child} -> :ok
          {:ok, _child, _info} -> :ok
          {:error, :already_present} -> :ok
          {:error, :running} -> :ok
          {:error, reason} -> raise("auth store did not restart: #{inspect(reason)}")
        end
    end

    wait_for_process!(Store, "auth store")
  end

  defp wait_for_process!(name, label, attempts \\ 40)

  defp wait_for_process!(_name, label, 0), do: raise("#{label} did not start")

  defp wait_for_process!(name, label, attempts) do
    case Process.whereis(name) do
      nil ->
        Process.sleep(50)
        wait_for_process!(name, label, attempts - 1)

      _pid ->
        :ok
    end
  end

  defp install_connection_for_start(
         connector_id,
         tenant_id,
         auth_type,
         profile_id,
         flow_kind,
         subject,
         opts,
         now
       ) do
    case Map.get(opts, :connection_id) do
      nil ->
        connection =
          Connection.new!(%{
            connection_id: Contracts.next_id("connection"),
            tenant_id: tenant_id,
            connector_id: connector_id,
            auth_type: auth_type,
            profile_id: profile_id,
            subject: subject,
            state: :installing,
            management_mode: Map.get(opts, :management_mode, default_management_mode(flow_kind)),
            secret_source: Map.get(opts, :secret_source),
            external_secret_ref: Map.get(opts, :external_secret_ref),
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
             {:ok, %Connection{} = installing_connection} <-
               transition_connection(connection, :installing) do
          installing_connection =
            %Connection{
              installing_connection
              | requested_scopes: Map.get(opts, :requested_scopes, connection.requested_scopes),
                profile_id: profile_id,
                management_mode:
                  Map.get(
                    opts,
                    :management_mode,
                    connection.management_mode || default_management_mode(flow_kind)
                  ),
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

  defp fetch_current_credential(%Connection{} = connection) do
    case current_credential_id(connection) do
      nil -> {:ok, nil}
      credential_id -> fetch_durable_credential(credential_id)
    end
  end

  defp fetch_active_credential(%Connection{} = connection) do
    connection
    |> current_credential_id()
    |> fetch_durable_credential()
  end

  defp build_credential(
         %Connection{} = connection,
         %Install{} = install,
         attrs,
         credential_ref_id,
         previous_credential
       ) do
    version = next_credential_version(previous_credential)

    Credential.new!(%{
      id: credential_id(credential_ref_id, version),
      credential_ref_id: credential_ref_id,
      connection_id: connection.connection_id,
      profile_id: connection.profile_id || install.profile_id,
      subject: connection.subject,
      auth_type: connection.auth_type,
      version: version,
      scopes: Map.get(attrs, :granted_scopes, connection.requested_scopes),
      secret: Map.get(attrs, :secret, %{}),
      lease_fields: Map.get(attrs, :lease_fields),
      expires_at: Map.get(attrs, :expires_at),
      refresh_token_expires_at: Map.get(attrs, :refresh_token_expires_at),
      source: Map.get(attrs, :source, default_credential_source(install.flow_kind)),
      source_ref: Map.get(attrs, :source_ref),
      supersedes_credential_id: previous_credential && previous_credential.id,
      metadata: Map.get(attrs, :metadata, %{})
    })
  end

  defp build_rotated_credential(%Credential{} = credential, %Connection{} = connection, attrs) do
    version = next_credential_version(credential)

    Credential.new!(%{
      id: credential_id(credential.credential_ref_id, version),
      credential_ref_id: credential.credential_ref_id,
      connection_id: connection.connection_id,
      profile_id: connection.profile_id || credential.profile_id,
      subject: connection.subject,
      auth_type: connection.auth_type,
      version: version,
      scopes: Map.get(attrs, :granted_scopes, credential.scopes),
      secret: Map.fetch!(attrs, :secret),
      lease_fields: Map.get(attrs, :lease_fields, credential.lease_fields),
      expires_at: Map.get(attrs, :expires_at, credential.expires_at),
      refresh_token_expires_at:
        Map.get(attrs, :refresh_token_expires_at, credential.refresh_token_expires_at),
      source: Map.get(attrs, :source, :rotation),
      source_ref: Map.get(attrs, :source_ref),
      supersedes_credential_id: credential.id,
      metadata: Map.get(attrs, :metadata, credential.metadata)
    })
  end

  defp build_credential_ref(
         %Credential{} = credential,
         %Connection{} = connection,
         install,
         credential_ref_id
       ) do
    CredentialRef.new!(%{
      id: credential_ref_id,
      connection_id: connection.connection_id,
      profile_id: credential.profile_id || connection.profile_id,
      subject: credential.subject,
      current_credential_id: credential.id,
      scopes: credential.scopes,
      lease_fields: credential.lease_fields,
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
        callback_received_at: Map.get(attrs, :callback_received_at),
        completed_at: now,
        updated_at: now
    }
  end

  defp terminalize_install(install_id, terminal_state, attrs) do
    attrs = Map.new(attrs)
    now = now(attrs)

    with {:ok, install} <- fetch_install(install_id),
         :ok <- ensure_install_terminalizable(install, terminal_state),
         terminal_install <- terminal_install_record(install, terminal_state, attrs, now),
         {:ok, connection} <-
           finalize_install_connection(terminal_install, terminal_state, attrs, now),
         :ok <- Stores.install_store().store_install(terminal_install) do
      {:ok, %{install: terminal_install, connection: connection}}
    end
  end

  defp maybe_refresh(%Connection{} = connection, %Credential{} = credential, now) do
    if Credential.expired?(credential, now) do
      with {:ok, %Connection{} = hydrated_connection, %Credential{} = hydrated_credential} <-
             hydrate_credential_secret(connection, credential, ["refresh_token"], now, :refresh),
           true <- refreshable?(hydrated_credential) or {:error, :credential_expired},
           handler when is_function(handler, 2) <-
             Store.refresh_handler() || {:error, :credential_expired},
           {:ok, refresh_result} <- handler.(hydrated_connection, hydrated_credential) do
        next_version = next_credential_version(hydrated_credential)

        refreshed_credential =
          Credential.new!(%{
            id: credential_id(hydrated_credential.credential_ref_id, next_version),
            credential_ref_id: hydrated_credential.credential_ref_id,
            connection_id: hydrated_credential.connection_id,
            profile_id: hydrated_credential.profile_id || hydrated_connection.profile_id,
            subject: hydrated_credential.subject,
            auth_type: hydrated_credential.auth_type,
            version: next_version,
            scopes: Map.get(refresh_result, :scopes, hydrated_credential.scopes),
            secret: Map.get(refresh_result, :secret, hydrated_credential.secret),
            lease_fields:
              Map.get(refresh_result, :lease_fields, hydrated_credential.lease_fields),
            expires_at: Map.get(refresh_result, :expires_at, hydrated_credential.expires_at),
            refresh_token_expires_at:
              Map.get(
                refresh_result,
                :refresh_token_expires_at,
                hydrated_credential.refresh_token_expires_at
              ),
            source: :refresh,
            source_ref: Map.get(refresh_result, :source_ref),
            supersedes_credential_id: hydrated_credential.id,
            metadata: Map.get(refresh_result, :metadata, hydrated_credential.metadata)
          })

        refreshed_connection =
          %Connection{
            hydrated_connection
            | state: :connected,
              current_credential_id: refreshed_credential.id,
              granted_scopes: refreshed_credential.scopes,
              lease_fields: refreshed_credential.lease_fields,
              token_expires_at: refreshed_credential.expires_at,
              last_refresh_at: now,
              last_refresh_status: :ok,
              degraded_reason: nil,
              reauth_required_reason: nil,
              updated_at: now
          }

        :ok = Stores.credential_store().store_credential(refreshed_credential)
        :ok = Stores.connection_store().store_connection(refreshed_connection)
        {:ok, refreshed_connection, refreshed_credential}
      else
        {:error, :reauth_required} ->
          {:error, :reauth_required}

        {:error, reason} ->
          mark_reauth_required(connection, now, reason)
      end
    else
      {:ok, connection, credential}
    end
  end

  defp mark_reauth_required(%Connection{} = connection, now, reason) do
    with {:ok, %Connection{} = reauth_connection} <-
           transition_connection(connection, :reauth_required) do
      reauth_connection = %Connection{
        reauth_connection
        | state: :reauth_required,
          last_refresh_at: now,
          last_refresh_status: :error,
          reauth_required_reason: normalize_reason(reason),
          updated_at: now
      }

      :ok = Stores.connection_store().store_connection(reauth_connection)
      {:error, :reauth_required}
    end
  end

  defp build_lease(
         %LeaseRecord{} = lease_record,
         %Connection{} = connection,
         %Credential{} = credential,
         payload
       ) do
    CredentialLease.new!(%{
      lease_id: lease_record.lease_id,
      credential_ref_id: lease_record.credential_ref_id,
      credential_id: lease_record.credential_id,
      connection_id: connection.connection_id,
      profile_id: lease_record.profile_id || connection.profile_id || credential.profile_id,
      subject: lease_record.subject,
      scopes: lease_record.scopes,
      payload: payload,
      lease_fields: lease_record.payload_keys,
      issued_at: lease_record.issued_at,
      expires_at: lease_record.expires_at,
      metadata: Map.merge(lease_record.metadata, %{connection_id: connection.connection_id})
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

  defp resolve_lease_payload(
         %Connection{} = connection,
         %Credential{} = credential,
         payload_keys,
         now,
         stage
       ) do
    with {:ok, hydrated_connection, hydrated_credential} <-
           hydrate_credential_secret(connection, credential, payload_keys, now, stage),
         payload <- Credential.lease_payload(hydrated_credential, payload_keys),
         [] <- missing_secret_fields(payload, payload_keys) do
      {:ok, hydrated_connection, payload}
    else
      missing_fields when is_list(missing_fields) ->
        {:error, {:missing_lease_fields, missing_fields}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp hydrate_credential_secret(
         %Connection{} = connection,
         %Credential{} = credential,
         requested_fields,
         now,
         stage
       ) do
    missing_fields = missing_secret_fields(credential.secret, requested_fields)

    cond do
      missing_fields == [] ->
        {:ok, connection, credential}

      external_secret_connection?(connection) ->
        resolve_external_secret(
          connection,
          credential,
          requested_fields,
          missing_fields,
          now,
          stage
        )

      true ->
        {:ok, connection, credential}
    end
  end

  defp resolve_external_secret(
         %Connection{} = connection,
         %Credential{} = credential,
         requested_fields,
         missing_fields,
         now,
         stage
       ) do
    opts = %{
      stage: stage,
      requested_fields: requested_fields,
      missing_fields: missing_fields,
      now: now
    }

    case Store.external_secret_resolver() do
      handler when is_function(handler, 3) ->
        handler.(connection, credential, opts)
        |> handle_external_secret_result(connection, credential, requested_fields, opts)

      _other ->
        record_external_secret_failure(connection, opts, :resolver_not_configured)
    end
  end

  defp handle_external_secret_result(
         {:ok, resolved_secret},
         %Connection{} = connection,
         %Credential{} = credential,
         requested_fields,
         opts
       )
       when is_map(resolved_secret) do
    merged_secret =
      credential.secret
      |> Map.merge(drop_nil_values(resolved_secret))

    case missing_secret_fields(merged_secret, requested_fields) do
      [] ->
        with {:ok, resolved_connection} <- record_external_secret_success(connection, opts) do
          {:ok, resolved_connection, %Credential{credential | secret: merged_secret}}
        end

      remaining_missing ->
        record_external_secret_failure(connection, opts, {:missing_fields, remaining_missing})
    end
  end

  defp handle_external_secret_result(
         {:error, reason},
         %Connection{} = connection,
         %Credential{},
         _requested_fields,
         opts
       ) do
    record_external_secret_failure(connection, opts, reason)
  end

  defp handle_external_secret_result(
         other,
         %Connection{} = connection,
         %Credential{},
         _requested_fields,
         opts
       ) do
    record_external_secret_failure(connection, opts, {:invalid_resolver_result, other})
  end

  defp record_external_secret_success(%Connection{} = connection, opts) do
    metadata =
      Map.put(
        connection.metadata,
        :external_secret_resolution,
        %{
          status: :ok,
          stage: opts.stage,
          requested_fields: opts.requested_fields,
          missing_fields: opts.missing_fields,
          resolved_at: opts.now
        }
      )

    connection =
      case transition_connection(connection, :connected) do
        {:ok, transitioned_connection} -> transitioned_connection
        {:error, _reason} -> connection
      end

    resolved_connection =
      %Connection{
        connection
        | state: :connected,
          degraded_reason: nil,
          metadata: metadata,
          updated_at: opts.now
      }

    :ok = Stores.connection_store().store_connection(resolved_connection)
    {:ok, resolved_connection}
  end

  defp record_external_secret_failure(%Connection{} = connection, opts, reason) do
    target_state = external_secret_failure_state(connection, opts.stage)
    normalized_reason = normalize_reason({:external_secret, reason})

    metadata =
      Map.put(
        connection.metadata,
        :external_secret_resolution,
        %{
          status: :error,
          stage: opts.stage,
          requested_fields: opts.requested_fields,
          missing_fields: opts.missing_fields,
          failed_at: opts.now,
          reason: normalized_reason
        }
      )

    connection =
      case transition_connection(connection, target_state) do
        {:ok, transitioned_connection} -> transitioned_connection
        {:error, _reason} -> connection
      end

    failed_connection =
      case target_state do
        :reauth_required ->
          %Connection{
            connection
            | state: :reauth_required,
              last_refresh_at: opts.now,
              last_refresh_status: :error,
              degraded_reason: nil,
              reauth_required_reason: normalized_reason,
              metadata: metadata,
              updated_at: opts.now
          }

        _other ->
          %Connection{
            connection
            | state: :degraded,
              degraded_reason: normalized_reason,
              metadata: metadata,
              updated_at: opts.now
          }
      end

    :ok = Stores.connection_store().store_connection(failed_connection)
    {:error, external_secret_failure_result(opts.stage)}
  end

  defp external_secret_connection?(%Connection{
         secret_source: :external_ref,
         external_secret_ref: external_secret_ref
       })
       when not is_nil(external_secret_ref),
       do: true

  defp external_secret_connection?(%Connection{external_secret_ref: external_secret_ref})
       when not is_nil(external_secret_ref),
       do: true

  defp external_secret_connection?(%Connection{secret_source: :external_ref}), do: true
  defp external_secret_connection?(%Connection{}), do: false

  defp external_secret_failure_state(%Connection{} = connection, :refresh) do
    metadata_value(connection.metadata, :external_secret_failure_state, :reauth_required)
    |> normalize_external_secret_failure_state()
  end

  defp external_secret_failure_state(%Connection{} = connection, _stage) do
    metadata_value(connection.metadata, :external_secret_failure_state, :degraded)
    |> normalize_external_secret_failure_state()
  end

  defp normalize_external_secret_failure_state(:reauth_required), do: :reauth_required
  defp normalize_external_secret_failure_state("reauth_required"), do: :reauth_required
  defp normalize_external_secret_failure_state(_other), do: :degraded

  defp external_secret_failure_result(:refresh), do: :reauth_required
  defp external_secret_failure_result(_stage), do: :external_secret_unavailable

  defp missing_secret_fields(secret, requested_fields)
       when is_map(secret) and is_list(requested_fields) do
    requested_fields
    |> Enum.map(&normalize_key/1)
    |> Enum.uniq()
    |> Enum.reject(fn field ->
      Enum.any?(Map.keys(secret), &(normalize_key(&1) == field))
    end)
  end

  defp missing_secret_fields(_secret, requested_fields) when is_list(requested_fields) do
    requested_fields
    |> Enum.map(&normalize_key/1)
    |> Enum.uniq()
  end

  defp metadata_value(metadata, key, default) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key), default))
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
      install.state not in [:installing, :awaiting_callback] ->
        {:error, :install_already_consumed}

      Install.expired?(install, now) ->
        {:error, :install_expired}

      true ->
        :ok
    end
  end

  defp ensure_callback_pending(%Install{state: :installing} = install, now) do
    if Install.expired?(install, now),
      do: {:error, :install_expired},
      else: :ok
  end

  defp ensure_callback_pending(%Install{state: :awaiting_callback}, _now),
    do: {:error, :callback_already_consumed}

  defp ensure_callback_pending(%Install{}, _now), do: {:error, :install_already_consumed}

  defp ensure_install_terminalizable(%Install{state: state}, state), do: :ok

  defp ensure_install_terminalizable(%Install{state: state}, _terminal_state)
       when state in [:installing, :awaiting_callback],
       do: :ok

  defp ensure_install_terminalizable(%Install{}, _terminal_state),
    do: {:error, :install_already_consumed}

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

  defp fetch_callback_install(attrs) when is_map(attrs) do
    cond do
      is_binary(Contracts.get(attrs, :install_id)) ->
        fetch_install(Contracts.fetch!(attrs, :install_id))

      is_binary(Contracts.get(attrs, :callback_token)) ->
        attrs
        |> Contracts.fetch!(:callback_token)
        |> fetch_install_by_filter(:callback_token)

      is_binary(Contracts.get(attrs, :state_token)) ->
        attrs
        |> Contracts.fetch!(:state_token)
        |> fetch_install_by_filter(:state_token)

      true ->
        {:error, :callback_locator_required}
    end
  end

  defp fetch_install_by_filter(value, key) when is_binary(value) do
    case Stores.install_store().list_installs(%{key => value}) do
      [install] -> {:ok, install}
      [] -> {:error, :unknown_install}
      _installs -> {:error, :ambiguous_install}
    end
  end

  defp validate_callback_token(%Install{} = install, attrs) do
    case Contracts.get(attrs, :callback_token) do
      nil ->
        :ok

      callback_token when callback_token == install.callback_token ->
        :ok

      _other ->
        {:error, :invalid_callback_token}
    end
  end

  defp validate_callback_state(%Install{state_token: nil}, _attrs), do: :ok

  defp validate_callback_state(%Install{state_token: state_token}, attrs) do
    if state_token == Contracts.get(attrs, :state_token),
      do: :ok,
      else: {:error, :invalid_callback_state}
  end

  defp validate_pkce_verifier(%Install{pkce_verifier_digest: nil}, _attrs), do: :ok

  defp validate_pkce_verifier(%Install{} = install, attrs) do
    case Contracts.get(attrs, :pkce_verifier) do
      verifier when is_binary(verifier) and verifier != "" ->
        if ArtifactBuilder.digest(verifier) == install.pkce_verifier_digest,
          do: :ok,
          else: {:error, :invalid_pkce_verifier}

      _other ->
        {:error, :pkce_verifier_required}
    end
  end

  defp maybe_fail_callback(%Install{} = install, attrs, now) do
    case callback_failure(attrs) do
      nil ->
        :ok

      reason ->
        fail_install(install.install_id, %{
          actor_id: Contracts.get(attrs, :actor_id),
          callback_received_at: Contracts.get(attrs, :callback_received_at, now),
          reason: {:callback, reason},
          now: now
        })

        {:error, {:callback_error, reason}}
    end
  end

  defp callback_failure(attrs) when is_map(attrs) do
    case {Map.get(attrs, :error), Map.get(attrs, :error_description)} do
      {nil, nil} ->
        case {Map.get(attrs, "error"), Map.get(attrs, "error_description")} do
          {nil, nil} -> nil
          {error, description} -> %{error: error, description: description}
        end

      {error, description} ->
        %{error: error, description: description}
    end
  end

  defp terminal_install_record(%Install{} = install, terminal_state, attrs, now) do
    reason = Contracts.get(attrs, :reason)

    base_install =
      %Install{
        install
        | state: terminal_state,
          callback_received_at:
            Contracts.get(attrs, :callback_received_at, install.callback_received_at),
          updated_at: now
      }

    case terminal_state do
      :cancelled ->
        %Install{
          base_install
          | cancelled_at: now,
            failure_reason: reason && normalize_reason(reason)
        }

      :failed ->
        %Install{
          base_install
          | failure_reason: normalize_reason(reason || :install_failed)
        }

      :expired ->
        %Install{
          base_install
          | failure_reason: normalize_reason(reason || :install_expired)
        }
    end
  end

  defp finalize_install_connection(%Install{} = install, terminal_state, attrs, now) do
    with {:ok, connection} <- Stores.connection_store().fetch_connection(install.connection_id) do
      resolved_connection =
        case restore_connection_from_snapshot(connection, install, attrs, now) do
          {:ok, restored_connection} ->
            restored_connection

          {:error, _reason} ->
            disable_install_connection(connection, terminal_state, attrs, now)
        end

      :ok = Stores.connection_store().store_connection(resolved_connection)
      {:ok, resolved_connection}
    end
  end

  defp restore_connection_from_snapshot(
         %Connection{} = connection,
         %Install{} = install,
         attrs,
         now
       ) do
    case install_snapshot(install) do
      nil ->
        {:error, :snapshot_unavailable}

      snapshot ->
        target_state = snapshot_connection_state(snapshot)

        with {:ok, %Connection{} = restored_connection} <-
               transition_connection(connection, target_state) do
          {:ok,
           %Connection{
             restored_connection
             | state: target_state,
               profile_id: metadata_value(snapshot, :profile_id, connection.profile_id),
               credential_ref_id:
                 metadata_value(snapshot, :credential_ref_id, connection.credential_ref_id),
               current_credential_ref_id:
                 metadata_value(
                   snapshot,
                   :current_credential_ref_id,
                   connection.current_credential_ref_id
                 ),
               current_credential_id:
                 metadata_value(
                   snapshot,
                   :current_credential_id,
                   connection.current_credential_id
                 ),
               install_id: metadata_value(snapshot, :install_id, connection.install_id),
               management_mode:
                 metadata_value(snapshot, :management_mode, connection.management_mode),
               secret_source: metadata_value(snapshot, :secret_source, connection.secret_source),
               external_secret_ref:
                 metadata_value(
                   snapshot,
                   :external_secret_ref,
                   connection.external_secret_ref
                 ),
               requested_scopes:
                 metadata_value(snapshot, :requested_scopes, connection.requested_scopes),
               granted_scopes:
                 metadata_value(snapshot, :granted_scopes, connection.granted_scopes),
               lease_fields: metadata_value(snapshot, :lease_fields, connection.lease_fields),
               token_expires_at:
                 metadata_value(snapshot, :token_expires_at, connection.token_expires_at),
               last_refresh_at:
                 metadata_value(snapshot, :last_refresh_at, connection.last_refresh_at),
               last_refresh_status:
                 metadata_value(snapshot, :last_refresh_status, connection.last_refresh_status),
               last_rotated_at:
                 metadata_value(snapshot, :last_rotated_at, connection.last_rotated_at),
               degraded_reason:
                 metadata_value(snapshot, :degraded_reason, connection.degraded_reason),
               reauth_required_reason:
                 metadata_value(
                   snapshot,
                   :reauth_required_reason,
                   connection.reauth_required_reason
                 ),
               disabled_reason:
                 metadata_value(snapshot, :disabled_reason, connection.disabled_reason),
               revoked_at: metadata_value(snapshot, :revoked_at, connection.revoked_at),
               revocation_reason:
                 metadata_value(snapshot, :revocation_reason, connection.revocation_reason),
               actor_id: Map.get(attrs, :actor_id, connection.actor_id),
               metadata: metadata_value(snapshot, :metadata, connection.metadata),
               updated_at: now
           }}
        end
    end
  end

  defp disable_install_connection(%Connection{} = connection, terminal_state, attrs, now) do
    reason = Contracts.get(attrs, :reason) || terminal_state

    actor_id = Contracts.get(attrs, :actor_id, connection.actor_id)

    case transition_connection(connection, :disabled) do
      {:ok, %Connection{} = disabled_connection} ->
        %Connection{
          disabled_connection
          | state: :disabled,
            degraded_reason: nil,
            reauth_required_reason: nil,
            disabled_reason: normalize_reason({:install, reason}),
            actor_id: actor_id,
            updated_at: now
        }

      {:error, _reason} ->
        %Connection{
          connection
          | state: :disabled,
            degraded_reason: nil,
            reauth_required_reason: nil,
            disabled_reason: normalize_reason({:install, reason}),
            actor_id: actor_id,
            updated_at: now
        }
    end
  end

  defp install_metadata(%Connection{} = connection, metadata, opts) when is_map(metadata) do
    if is_binary(Map.get(opts, :connection_id)) do
      reauth_snapshot =
        case Map.get(opts, :reauth_snapshot) do
          snapshot when is_map(snapshot) -> snapshot
          _other -> connection_snapshot(connection)
        end

      metadata
      |> Map.put_new(:install_origin, :reauth)
      |> Map.put_new(:reauth_snapshot, reauth_snapshot)
    else
      metadata
      |> Map.put_new(:install_origin, :new_connection)
    end
  end

  defp install_metadata(%Connection{}, metadata, _opts), do: metadata

  defp connection_snapshot(%Connection{} = connection) do
    connection
    |> Map.from_struct()
    |> Map.take([
      :state,
      :credential_ref_id,
      :current_credential_ref_id,
      :current_credential_id,
      :install_id,
      :management_mode,
      :secret_source,
      :external_secret_ref,
      :requested_scopes,
      :granted_scopes,
      :lease_fields,
      :token_expires_at,
      :last_refresh_at,
      :last_refresh_status,
      :last_rotated_at,
      :degraded_reason,
      :reauth_required_reason,
      :disabled_reason,
      :revoked_at,
      :revocation_reason,
      :profile_id,
      :metadata
    ])
  end

  defp install_snapshot(%Install{} = install) do
    install.metadata
    |> metadata_value(:reauth_snapshot, nil)
    |> case do
      snapshot when is_map(snapshot) -> snapshot
      _other -> nil
    end
  end

  defp snapshot_connection_state(snapshot) when is_map(snapshot) do
    snapshot
    |> metadata_value(:state, :disabled)
    |> normalize_snapshot_connection_state()
  end

  defp normalize_snapshot_connection_state(:connected), do: :connected
  defp normalize_snapshot_connection_state("connected"), do: :connected
  defp normalize_snapshot_connection_state(:degraded), do: :degraded
  defp normalize_snapshot_connection_state("degraded"), do: :degraded
  defp normalize_snapshot_connection_state(:reauth_required), do: :reauth_required
  defp normalize_snapshot_connection_state("reauth_required"), do: :reauth_required
  defp normalize_snapshot_connection_state(:revoked), do: :revoked
  defp normalize_snapshot_connection_state("revoked"), do: :revoked
  defp normalize_snapshot_connection_state(:disabled), do: :disabled
  defp normalize_snapshot_connection_state("disabled"), do: :disabled
  defp normalize_snapshot_connection_state(_other), do: :disabled

  defp connection_id(%CredentialRef{} = credential_ref, %Credential{} = credential) do
    if is_binary(credential_ref.connection_id) do
      credential_ref.connection_id
    else
      metadata = Map.get(credential_ref, :metadata, %{})

      Map.get(
        metadata,
        :connection_id,
        Map.get(metadata, "connection_id", credential.connection_id)
      )
    end
  end

  defp current_credential_id(%Connection{} = connection) do
    connection.current_credential_id || connection.credential_ref_id
  end

  defp current_credential_id(%CredentialRef{} = credential_ref) do
    credential_ref.current_credential_id || credential_ref.id
  end

  defp credential_ref_id(connection_id), do: "cred:" <> connection_id

  defp credential_id(credential_ref_id, 1), do: credential_ref_id
  defp credential_id(credential_ref_id, version), do: "#{credential_ref_id}:v#{version}"

  defp next_credential_version(nil), do: 1
  defp next_credential_version(%Credential{version: version}), do: version + 1

  defp default_profile_id, do: "default"

  defp default_flow_kind(:oauth2), do: :manual_callback
  defp default_flow_kind(:app_installation), do: :provider_install
  defp default_flow_kind(_auth_type), do: :manual

  defp default_management_mode(:provider_install), do: :provider_app
  defp default_management_mode(_flow_kind), do: :manual

  defp default_secret_source(:provider_install), do: :hosted_callback
  defp default_secret_source(:manual_callback), do: :hosted_callback
  defp default_secret_source(_flow_kind), do: :manual

  defp default_credential_source(:provider_install), do: :hosted_callback
  defp default_credential_source(:manual_callback), do: :hosted_callback
  defp default_credential_source(_flow_kind), do: :manual

  defp normalize_reason(reason) when is_binary(reason), do: reason
  defp normalize_reason(reason), do: inspect(reason)

  defp now(map), do: Contracts.get(map, :now, Contracts.now())

  defp enrich_install_opts(opts) when is_map(opts) do
    case Map.get(opts, :connection_id) do
      connection_id when is_binary(connection_id) ->
        case Stores.connection_store().fetch_connection(connection_id) do
          {:ok, connection} ->
            Map.put_new(opts, :reauth_snapshot, connection_snapshot(connection))

          {:error, _reason} ->
            opts
        end

      _other ->
        opts
    end
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key

  defp drop_nil_values(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp reset_store(module) do
    if function_exported?(module, :reset!, 0) do
      module.reset!()
    end
  end
end
