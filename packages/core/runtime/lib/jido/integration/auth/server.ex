defmodule Jido.Integration.Auth.Server do
  @moduledoc """
  Auth server — the canonical auth lifecycle engine for the substrate.

  `Auth.Server` owns credential storage, connection lifecycle transitions,
  scope enforcement, install-session validation, callback finalization, and
  token refresh coordination.

  Host-facing integrations should wrap this engine through
  `Jido.Integration.Auth.Bridge` rather than reimplementing lifecycle rules in
  controllers or framework glue.
  """

  use GenServer

  alias Jido.Integration.Auth.{
    Connection,
    ConnectionStore,
    Credential,
    InstallSession,
    InstallSessionStore,
    Store
  }

  alias Jido.Integration.Telemetry

  @blocked_states [:reauth_required, :revoked, :disabled]
  @default_install_session_ttl_ms 10 * 60 * 1000

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Store a credential, returns auth_ref in format `auth:<connector>:<scope_id>`."
  @spec store_credential(GenServer.server(), String.t(), String.t(), Credential.t()) ::
          {:ok, String.t()}
  def store_credential(server, connector_type, scope_id, %Credential{} = cred) do
    GenServer.call(server, {:store_credential, connector_type, scope_id, cred})
  end

  @doc """
  Resolve a credential by auth_ref with scope enforcement.

  Context can include `:connector_id`, `:trace_id`, `:span_id`, and `:actor_id`.
  If the credential is an expired OAuth2 token with a refresh_token, refresh is
  coordinated outside the GenServer and deduplicated per `auth_ref`.
  """
  @spec resolve_credential(GenServer.server(), String.t(), map()) ::
          {:ok, Credential.t()}
          | {:error,
             :not_found | :expired | :scope_violation | :refresh_failed | :refresh_retryable}
  def resolve_credential(server, auth_ref, context) do
    GenServer.call(server, {:resolve_credential, auth_ref, context}, :infinity)
  end

  @doc "Replace the credential at an existing auth_ref."
  @spec rotate_credential(GenServer.server(), String.t(), Credential.t()) ::
          :ok | {:error, :not_found}
  def rotate_credential(server, auth_ref, %Credential{} = new_cred) do
    GenServer.call(server, {:rotate_credential, auth_ref, new_cred})
  end

  @doc "Remove a credential."
  @spec revoke_credential(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  def revoke_credential(server, auth_ref) do
    GenServer.call(server, {:revoke_credential, auth_ref})
  end

  @doc "List all credentials for a connector type."
  @spec list_credentials(GenServer.server(), String.t()) :: [{String.t(), Credential.t()}]
  def list_credentials(server, connector_type) do
    GenServer.call(server, {:list_credentials, connector_type})
  end

  @doc "Set the refresh callback function for transparent token refresh."
  @spec set_refresh_callback(GenServer.server(), (String.t(), String.t() ->
                                                    {:ok, map()} | {:error, term()})) :: :ok
  def set_refresh_callback(server, callback) when is_function(callback, 2) do
    GenServer.call(server, {:set_refresh_callback, callback})
  end

  @doc "Create a new connection."
  @spec create_connection(GenServer.server(), String.t(), String.t(), keyword()) ::
          {:ok, Connection.t()}
  def create_connection(server, connector_id, tenant_id, opts \\ []) do
    GenServer.call(server, {:create_connection, connector_id, tenant_id, opts})
  end

  @doc """
  Start an install flow for a connector/tenant pair.

  Host bridges call this after resolving the actor, tenant, and runtime
  instance from host request context.

  Options can include:
  - `:scopes`
  - `:actor_id`
  - `:auth_base_url`
  - `:connection_id` to reuse an existing connection during re-consent
  - `:pkce_required`
  - `:auth_descriptor_id`
  - `:auth_type`
  - `:telemetry_context`
  """
  @spec start_install(GenServer.server(), String.t(), String.t(), map() | keyword()) ::
          {:ok, %{auth_url: String.t(), session_state: map(), connection_id: String.t()}}
          | {:error, term()}
  def start_install(server, connector_id, tenant_id, opts \\ %{}) do
    GenServer.call(server, {:start_install, connector_id, tenant_id, normalize_opts(opts)})
  end

  @doc """
  Handle the callback for a previously-started install session.

  Host bridges own the HTTP boundary and request parsing. `Auth.Server`
  remains responsible for state-token validation, anti-replay handling,
  credential creation, and final connection state transitions.

  `params` may contain:
  - `"state"`
  - `"credential"` or raw OAuth fields (`access_token`, `refresh_token`, `expires_at`)
  - `"granted_scopes"` or `"scope"`
  - `"actor_id"`
  """
  @spec handle_callback(GenServer.server(), String.t(), map(), map()) ::
          {:ok, %{connection_id: String.t(), state: Connection.state(), auth_ref: String.t()}}
          | {:error, term()}
  def handle_callback(server, connector_id, params, session_state) do
    GenServer.call(server, {:handle_callback, connector_id, params, session_state})
  end

  @doc "Get a connection by ID."
  @spec get_connection(GenServer.server(), String.t()) ::
          {:ok, Connection.t()} | {:error, :not_found}
  def get_connection(server, connection_id) do
    GenServer.call(server, {:get_connection, connection_id})
  end

  @doc "Transition a connection to a new state."
  @spec transition_connection(GenServer.server(), String.t(), Connection.state(), String.t()) ::
          {:ok, Connection.t()} | {:error, String.t()}
  def transition_connection(server, connection_id, to_state, actor_id) do
    transition_connection(server, connection_id, to_state, actor_id, [])
  end

  @spec transition_connection(
          GenServer.server(),
          String.t(),
          Connection.state(),
          String.t(),
          keyword()
        ) :: {:ok, Connection.t()} | {:error, String.t()}
  def transition_connection(server, connection_id, to_state, actor_id, opts) do
    GenServer.call(server, {:transition_connection, connection_id, to_state, actor_id, opts})
  end

  @doc "Check if a connection has the required scopes and is allowed to execute."
  @spec check_connection_scopes(GenServer.server(), String.t(), [String.t()], keyword()) ::
          :ok
          | {:error,
             :not_found
             | :connector_mismatch
             | %{missing_scopes: [String.t()]}
             | {:blocked_state, atom()}}
  def check_connection_scopes(server, connection_id, required_scopes, opts \\ []) do
    GenServer.call(server, {:check_connection_scopes, connection_id, required_scopes, opts})
  end

  @doc "Link a connection to an auth_ref for refresh-failure state transitions."
  @spec link_connection(GenServer.server(), String.t(), String.t()) :: :ok
  def link_connection(server, connection_id, auth_ref) do
    GenServer.call(server, {:link_connection, connection_id, auth_ref})
  end

  @doc "Emit the chartered rotation_overdue degradation event."
  @spec mark_rotation_overdue(GenServer.server(), String.t(), String.t(), keyword()) ::
          {:ok, Connection.t()} | {:error, String.t()}
  def mark_rotation_overdue(
        server,
        connection_id,
        actor_id \\ "system:rotation_overdue",
        opts \\ []
      ) do
    transition_connection(
      server,
      connection_id,
      :degraded,
      actor_id,
      Keyword.put(opts, :reason, :rotation_overdue)
    )
  end

  # Server

  @impl GenServer
  def init(opts) do
    store_module = Keyword.get(opts, :store_module, Store.Disk)
    connection_store_module = Keyword.get(opts, :connection_store_module, ConnectionStore.Disk)

    install_session_store_module =
      Keyword.get(opts, :install_session_store_module, InstallSessionStore.Disk)

    {:ok, store_server} =
      store_module.start_link(Keyword.put_new(store_opts(opts, :store_opts), :name, nil))

    {:ok, connection_store_server} =
      connection_store_module.start_link(
        Keyword.put_new(store_opts(opts, :connection_store_opts), :name, nil)
      )

    {:ok, install_session_store_server} =
      install_session_store_module.start_link(
        Keyword.put_new(store_opts(opts, :install_session_store_opts), :name, nil)
      )

    {:ok,
     %{
       store_module: store_module,
       store_server: store_server,
       connection_store_module: connection_store_module,
       connection_store_server: connection_store_server,
       install_session_store_module: install_session_store_module,
       install_session_store_server: install_session_store_server,
       refresh_callback: nil,
       ref_to_conn: load_ref_to_conn(connection_store_module, connection_store_server),
       install_session_ttl_ms:
         Keyword.get(opts, :install_session_ttl_ms, @default_install_session_ttl_ms),
       refresh_waiters: %{},
       refresh_monitors: %{}
     }}
  end

  @impl GenServer
  def handle_call({:store_credential, connector_type, scope_id, cred}, _from, state) do
    auth_ref = "auth:#{connector_type}:#{scope_id}"
    :ok = state.store_module.store(state.store_server, auth_ref, cred)

    emit_auth("jido.integration.auth.install.succeeded", %{
      auth_ref: auth_ref,
      connector_id: connector_type,
      auth_type: cred.type,
      state: :connected
    })

    {:reply, {:ok, auth_ref}, state}
  end

  @impl GenServer
  def handle_call({:resolve_credential, auth_ref, context}, from, state) do
    connector_id = context_value(context, :connector_id)

    case state.store_module.fetch(state.store_server, auth_ref,
           connector_id: connector_id,
           allow_expired: true
         ) do
      {:ok, cred} ->
        if Credential.expired?(cred) do
          maybe_begin_refresh(from, auth_ref, cred, context, state)
        else
          {:reply, {:ok, cred}, state}
        end

      {:error, :scope_violation} ->
        emit_auth("jido.integration.auth.scope.mismatch", %{
          auth_ref: auth_ref,
          connector_id: connector_id,
          trace_id: context_value(context, :trace_id),
          span_id: context_value(context, :span_id),
          actor_id: context_value(context, :actor_id),
          failure_class: :scope_violation
        })

        {:reply, {:error, :scope_violation}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:rotate_credential, auth_ref, new_cred}, _from, state) do
    case state.store_module.fetch(state.store_server, auth_ref, allow_expired: true) do
      {:ok, _} ->
        :ok = state.store_module.store(state.store_server, auth_ref, new_cred)

        emit_auth("jido.integration.auth.rotated", %{
          auth_ref: auth_ref,
          connector_id: parse_connector_type(auth_ref),
          auth_type: new_cred.type
        })

        {:reply, :ok, state}

      {:error, :expired} ->
        :ok = state.store_module.store(state.store_server, auth_ref, new_cred)

        emit_auth("jido.integration.auth.rotated", %{
          auth_ref: auth_ref,
          connector_id: parse_connector_type(auth_ref),
          auth_type: new_cred.type
        })

        {:reply, :ok, state}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}

      {:error, _reason} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:revoke_credential, auth_ref}, _from, state) do
    case state.store_module.delete(state.store_server, auth_ref) do
      :ok ->
        {conn_id, ref_to_conn} = Map.pop(state.ref_to_conn, auth_ref)

        if conn_id do
          :ok = clear_connection_auth_ref(state, conn_id)
        end

        emit_auth("jido.integration.auth.revoked", %{
          auth_ref: auth_ref,
          connector_id: parse_connector_type(auth_ref)
        })

        {:reply, :ok, %{state | ref_to_conn: ref_to_conn}}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:list_credentials, connector_type}, _from, state) do
    {:reply, state.store_module.list(state.store_server, connector_type), state}
  end

  @impl GenServer
  def handle_call({:set_refresh_callback, callback}, _from, state) do
    {:reply, :ok, %{state | refresh_callback: callback}}
  end

  @impl GenServer
  def handle_call({:create_connection, connector_id, tenant_id, opts}, _from, state) do
    scopes = Keyword.get(opts, :scopes, [])
    conn = Connection.new(connector_id, tenant_id)
    conn = %{conn | scopes: scopes}
    :ok = persist_connection(state, conn)
    {:reply, {:ok, conn}, state}
  end

  @impl GenServer
  def handle_call({:start_install, connector_id, tenant_id, opts}, _from, state) do
    actor_id = fetch_opt(opts, :actor_id, "system:install")
    telemetry_context = fetch_opt(opts, :telemetry_context, %{})
    requested_scopes = fetch_opt(opts, :scopes, [])

    case install_connection(
           state,
           connector_id,
           tenant_id,
           requested_scopes,
           actor_id,
           opts
         ) do
      {:ok, conn, install_state} ->
        session =
          build_install_session(
            conn,
            connector_id,
            tenant_id,
            requested_scopes,
            actor_id,
            opts,
            install_state
          )

        case persist_install_session(install_state, session) do
          :ok ->
            auth_url = build_auth_url(connector_id, tenant_id, session, opts)

            emit_auth("jido.integration.auth.install.started", %{
              connector_id: connector_id,
              tenant_id: tenant_id,
              auth_descriptor_id: fetch_opt(opts, :auth_descriptor_id, "oauth2"),
              auth_type: fetch_opt(opts, :auth_type, :oauth2),
              state: conn.state,
              actor_id: actor_id,
              trace_id: context_value(telemetry_context, :trace_id),
              span_id: context_value(telemetry_context, :span_id)
            })

            reply = %{
              auth_url: auth_url,
              connection_id: conn.id,
              session_state: session_state_payload(session)
            }

            {:reply, {:ok, reply}, install_state}

          {:error, reason} ->
            emit_auth("jido.integration.auth.install.failed", %{
              connector_id: connector_id,
              tenant_id: tenant_id,
              auth_descriptor_id: fetch_opt(opts, :auth_descriptor_id, "oauth2"),
              auth_type: fetch_opt(opts, :auth_type, :oauth2),
              failure_class: normalize_failure_reason(reason),
              actor_id: actor_id,
              trace_id: context_value(telemetry_context, :trace_id),
              span_id: context_value(telemetry_context, :span_id)
            })

            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        emit_auth("jido.integration.auth.install.failed", %{
          connector_id: connector_id,
          tenant_id: tenant_id,
          auth_descriptor_id: fetch_opt(opts, :auth_descriptor_id, "oauth2"),
          auth_type: fetch_opt(opts, :auth_type, :oauth2),
          failure_class: :invalid_request,
          actor_id: actor_id,
          trace_id: context_value(telemetry_context, :trace_id),
          span_id: context_value(telemetry_context, :span_id)
        })

        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:handle_callback, connector_id, params, session_state}, _from, state) do
    context = callback_context(params, session_state)

    with {:ok, session, state} <-
           consume_install_session(state, connector_id, params, session_state),
         {:ok, credential} <- build_callback_credential(params, session),
         {:ok, result, state} <- finalize_install(state, session, credential, params, context) do
      {:reply, {:ok, result}, state}
    else
      {:error, reason, state} ->
        emit_auth("jido.integration.auth.install.failed", %{
          connector_id: connector_id,
          tenant_id: context_value(session_state, :tenant_id),
          auth_descriptor_id: context_value(session_state, :auth_descriptor_id) || "oauth2",
          auth_type: context_value(session_state, :auth_type) || :oauth2,
          failure_class: normalize_failure_reason(reason),
          actor_id: context_value(context, :actor_id),
          trace_id: context_value(context, :trace_id),
          span_id: context_value(context, :span_id)
        })

        {:reply, {:error, reason}, state}

      {:error, reason} ->
        emit_auth("jido.integration.auth.install.failed", %{
          connector_id: connector_id,
          tenant_id: context_value(session_state, :tenant_id),
          auth_descriptor_id: context_value(session_state, :auth_descriptor_id) || "oauth2",
          auth_type: context_value(session_state, :auth_type) || :oauth2,
          failure_class: normalize_failure_reason(reason),
          actor_id: context_value(context, :actor_id),
          trace_id: context_value(context, :trace_id),
          span_id: context_value(context, :span_id)
        })

        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_connection, connection_id}, _from, state) do
    {:reply, fetch_connection(state, connection_id), state}
  end

  @impl GenServer
  def handle_call({:transition_connection, connection_id, to_state, actor_id, opts}, _from, state) do
    case fetch_connection(state, connection_id) do
      {:ok, conn} ->
        case Connection.transition(conn, to_state, actor_id) do
          {:ok, transitioned} ->
            {final_conn, new_state} =
              handle_transition_side_effects(transitioned, conn, to_state, actor_id, opts, state)

            :ok = persist_connection(new_state, final_conn)
            {:reply, {:ok, final_conn}, new_state}

          {:error, _} = err ->
            {:reply, err, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, "Connection not found: #{connection_id}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:check_connection_scopes, connection_id, required_scopes, opts}, _from, state) do
    context = Keyword.get(opts, :context, %{})
    connector_id = Keyword.get(opts, :connector_id)

    result =
      case fetch_connection(state, connection_id) do
        {:ok, conn} ->
          cond do
            connector_id && conn.connector_id != connector_id ->
              emit_scope_mismatch(conn, context, required_scopes,
                failure_class: :connector_mismatch,
                expected_connector_id: connector_id
              )

              {:error, :connector_mismatch}

            conn.state in @blocked_states ->
              emit_auth("jido.integration.auth.scope.gated", %{
                tenant_id: conn.tenant_id,
                connector_id: conn.connector_id,
                state: conn.state,
                actor_id: context_value(context, :actor_id),
                trace_id: context_value(context, :trace_id),
                span_id: context_value(context, :span_id),
                missing_scopes: required_scopes
              })

              {:error, {:blocked_state, conn.state}}

            true ->
              check_required_scopes(conn, required_scopes, context)
          end

        {:error, :not_found} ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:link_connection, connection_id, auth_ref}, _from, state) do
    state =
      case fetch_connection(state, connection_id) do
        {:ok, conn} ->
          updated = %{conn | auth_ref: auth_ref, updated_at: DateTime.utc_now()}
          :ok = persist_connection(state, updated)
          %{state | ref_to_conn: Map.put(state.ref_to_conn, auth_ref, connection_id)}

        {:error, :not_found} ->
          %{state | ref_to_conn: Map.put(state.ref_to_conn, auth_ref, connection_id)}
      end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:refresh_result, auth_ref, context, {:ok, token_data}}, state) do
    case Map.get(state.refresh_waiters, auth_ref) do
      nil ->
        {:noreply, state}

      refresh ->
        {:ok, current} =
          state.store_module.fetch(state.store_server, auth_ref,
            allow_expired: true,
            connector_id: context_value(context, :connector_id)
          )

        new_cred = apply_refresh(current, token_data)
        :ok = state.store_module.store(state.store_server, auth_ref, new_cred)

        emit_auth("jido.integration.auth.token.refreshed", %{
          auth_ref: auth_ref,
          connector_id: parse_connector_type(auth_ref),
          auth_type: new_cred.type,
          state: :connected,
          actor_id: context_value(context, :actor_id),
          trace_id: context_value(context, :trace_id),
          span_id: context_value(context, :span_id)
        })

        reply_refresh_waiters(refresh.waiters, {:ok, new_cred})
        {:noreply, clear_refresh(auth_ref, state)}
    end
  end

  @impl GenServer
  def handle_info({:refresh_result, auth_ref, context, {:error, reason}}, state) do
    {:noreply, fail_refresh(auth_ref, context, reason, state)}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.refresh_monitors, ref) do
      {nil, _monitors} ->
        {:noreply, state}

      {auth_ref, monitors} ->
        state = %{state | refresh_monitors: monitors}

        if Map.has_key?(state.refresh_waiters, auth_ref) do
          context = state.refresh_waiters[auth_ref].context
          {:noreply, fail_refresh(auth_ref, context, reason, state)}
        else
          {:noreply, state}
        end
    end
  end

  # Internal helpers

  defp maybe_begin_refresh(_from, _auth_ref, cred, _context, state)
       when not is_struct(cred, Credential) do
    {:reply, {:error, :expired}, state}
  end

  defp maybe_begin_refresh(_from, _auth_ref, cred, _context, state)
       when not is_binary(cred.refresh_token) do
    {:reply, {:error, :expired}, state}
  end

  defp maybe_begin_refresh(_from, _auth_ref, _cred, _context, %{refresh_callback: nil} = state) do
    {:reply, {:error, :expired}, state}
  end

  defp maybe_begin_refresh(from, auth_ref, cred, context, state) do
    case Map.get(state.refresh_waiters, auth_ref) do
      nil ->
        parent = self()

        {_pid, monitor_ref} =
          spawn_monitor(fn ->
            result = state.refresh_callback.(auth_ref, cred.refresh_token)
            send(parent, {:refresh_result, auth_ref, context, result})
          end)

        refresh_waiters =
          Map.put(state.refresh_waiters, auth_ref, %{waiters: [from], context: context})

        refresh_monitors = Map.put(state.refresh_monitors, monitor_ref, auth_ref)

        {:noreply,
         %{state | refresh_waiters: refresh_waiters, refresh_monitors: refresh_monitors}}

      refresh ->
        updated = %{refresh | waiters: refresh.waiters ++ [from]}
        {:noreply, put_in(state.refresh_waiters[auth_ref], updated)}
    end
  end

  defp fail_refresh(auth_ref, context, reason, state) do
    case Map.get(state.refresh_waiters, auth_ref) do
      nil ->
        state

      refresh ->
        failure_class = classify_refresh_failure(reason)
        state = maybe_transition_connection(auth_ref, failure_class, state)

        emit_auth("jido.integration.auth.token.refresh_failed", %{
          auth_ref: auth_ref,
          connector_id: parse_connector_type(auth_ref),
          failure_class: failure_class,
          state: connection_state_for_ref(auth_ref, state),
          actor_id: context_value(context, :actor_id),
          trace_id: context_value(context, :trace_id),
          span_id: context_value(context, :span_id),
          reason: normalize_failure_reason(reason)
        })

        reply =
          case failure_class do
            :terminal -> {:error, :refresh_failed}
            _ -> {:error, :refresh_retryable}
          end

        reply_refresh_waiters(refresh.waiters, reply)
        clear_refresh(auth_ref, state)
    end
  end

  defp clear_refresh(auth_ref, state) do
    monitor_refs =
      state.refresh_monitors
      |> Enum.filter(fn {_ref, waiting_auth_ref} -> waiting_auth_ref == auth_ref end)
      |> Enum.map(&elem(&1, 0))

    refresh_monitors = Map.drop(state.refresh_monitors, monitor_refs)

    %{
      state
      | refresh_waiters: Map.delete(state.refresh_waiters, auth_ref),
        refresh_monitors: refresh_monitors
    }
  end

  defp reply_refresh_waiters(waiters, reply) do
    Enum.each(waiters, &GenServer.reply(&1, reply))
  end

  defp apply_refresh(%Credential{} = cred, token_data) do
    %{
      cred
      | access_token: token_data.access_token,
        refresh_token: Map.get(token_data, :refresh_token, cred.refresh_token),
        expires_at: Map.get(token_data, :expires_at, cred.expires_at)
    }
  end

  defp install_connection(state, connector_id, tenant_id, requested_scopes, actor_id, opts) do
    case fetch_opt(opts, :connection_id) do
      nil ->
        install_new_connection(state, connector_id, tenant_id, requested_scopes, actor_id)

      connection_id ->
        install_existing_connection(
          state,
          connection_id,
          connector_id,
          tenant_id,
          requested_scopes,
          actor_id
        )
    end
  end

  defp install_new_connection(state, connector_id, tenant_id, requested_scopes, actor_id) do
    conn = Connection.new(connector_id, tenant_id)
    conn = %{conn | scopes: requested_scopes}

    with {:ok, installing} <- Connection.transition(conn, :installing, actor_id) do
      :ok = persist_connection(state, installing)
      {:ok, installing, state}
    end
  end

  defp install_existing_connection(
         state,
         connection_id,
         connector_id,
         tenant_id,
         requested_scopes,
         actor_id
       ) do
    case fetch_connection(state, connection_id) do
      {:ok, conn} when conn.connector_id == connector_id and conn.tenant_id == tenant_id ->
        persist_install_transition(state, conn, requested_scopes, actor_id)

      {:ok, _conn} ->
        {:error, :connector_mismatch}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp persist_install_transition(state, conn, requested_scopes, actor_id) do
    with {:ok, updated} <- maybe_transition_for_install(conn, actor_id) do
      updated = %{updated | scopes: requested_scopes}
      :ok = persist_connection(state, updated)
      {:ok, updated, state}
    end
  end

  defp maybe_transition_for_install(%Connection{state: :installing} = conn, _actor_id),
    do: {:ok, conn}

  defp maybe_transition_for_install(%Connection{} = conn, actor_id),
    do: Connection.transition(conn, :installing, actor_id)

  defp build_install_session(
         conn,
         connector_id,
         tenant_id,
         requested_scopes,
         actor_id,
         opts,
         state
       ) do
    now = DateTime.utc_now()
    pkce_required = fetch_opt(opts, :pkce_required, false)
    code_verifier = if pkce_required, do: generate_token(), else: nil
    telemetry_context = fetch_opt(opts, :telemetry_context, %{})

    {:ok, session} =
      InstallSession.new(%{
        state_token: generate_token(),
        nonce: generate_token(),
        connector_id: connector_id,
        tenant_id: tenant_id,
        connection_id: conn.id,
        actor_id: actor_id,
        auth_descriptor_id: fetch_opt(opts, :auth_descriptor_id, "oauth2"),
        auth_type: fetch_opt(opts, :auth_type, :oauth2),
        requested_scopes: requested_scopes,
        code_verifier: code_verifier,
        code_challenge: if(pkce_required, do: pkce_challenge(code_verifier), else: nil),
        trace_id: context_value(telemetry_context, :trace_id),
        span_id: context_value(telemetry_context, :span_id),
        created_at: now,
        expires_at: DateTime.add(now, div(state.install_session_ttl_ms, 1000), :second)
      })

    session
  end

  defp build_auth_url(connector_id, tenant_id, session, opts) do
    base_url =
      fetch_opt(opts, :auth_base_url, "https://auth.example/#{connector_id}/authorize")

    query =
      %{
        "state" => session.state_token,
        "nonce" => session.nonce,
        "tenant_id" => tenant_id,
        "scope" => Enum.join(session.requested_scopes, " ")
      }
      |> maybe_put("code_challenge", session.code_challenge)
      |> URI.encode_query()

    base_url <> "?" <> query
  end

  defp consume_install_session(state, connector_id, params, session_state) do
    submitted_state =
      context_value(params, :state) ||
        context_value(session_state, :state)

    with state_token when is_binary(state_token) <- submitted_state,
         {:ok, session} <- fetch_install_session(state, state_token),
         :ok <- validate_install_session(connector_id, params, session_state, session),
         {:ok, consumed} <- consume_install_session_record(state, state_token) do
      {:ok, consumed, state}
    else
      nil -> {:error, :invalid_state_token, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp fetch_install_session(state, state_token) do
    case state.install_session_store_module.fetch(
           state.install_session_store_server,
           state_token,
           allow_expired: true
         ) do
      {:ok, %InstallSession{} = session} -> {:ok, session}
      {:error, :not_found} -> {:error, :invalid_state_token}
      {:error, :expired} -> {:error, :state_expired}
    end
  end

  defp consume_install_session_record(state, state_token) do
    case state.install_session_store_module.consume(
           state.install_session_store_server,
           state_token
         ) do
      {:ok, %InstallSession{} = session} -> {:ok, session}
      {:error, :not_found} -> {:error, :invalid_state_token}
      {:error, :already_consumed} -> {:error, :invalid_state_token}
      {:error, :expired} -> {:error, :state_expired}
    end
  end

  defp validate_install_session(connector_id, _params, session_state, session) do
    cond do
      session.connector_id != connector_id ->
        {:error, :connector_mismatch}

      DateTime.compare(session.expires_at, DateTime.utc_now()) == :lt ->
        {:error, :state_expired}

      session.code_challenge &&
          pkce_challenge(context_value(session_state, :code_verifier)) != session.code_challenge ->
        {:error, :pkce_verification_failed}

      true ->
        :ok
    end
  end

  defp build_callback_credential(params, session) do
    scopes = granted_scopes(params, session.requested_scopes)
    raw = context_value(params, :credential)

    cond do
      is_struct(raw, Credential) ->
        {:ok, %{raw | scopes: scopes}}

      is_map(raw) ->
        raw
        |> callback_credential_attrs(scopes)
        |> Credential.new()

      true ->
        params
        |> callback_credential_attrs(scopes)
        |> Credential.new()
    end
  end

  defp callback_credential_attrs(params, scopes) do
    %{
      type: :oauth2,
      access_token: context_value(params, :access_token),
      refresh_token: context_value(params, :refresh_token),
      expires_at: parse_datetime(context_value(params, :expires_at)),
      token_semantics: context_value(params, :token_semantics) || "bearer",
      scopes: scopes
    }
  end

  defp finalize_install(state, session, credential, params, context) do
    auth_ref = connection_auth_ref(session.connector_id, session.connection_id)
    actor_id = context_value(params, :actor_id) || session.actor_id || "system:callback"

    with {:ok, conn} <- fetch_connection(state, session.connection_id),
         :ok <- state.store_module.store(state.store_server, auth_ref, credential),
         {:ok, connected} <-
           Connection.transition(%{conn | scopes: credential.scopes}, :connected, actor_id) do
      connected = %{connected | auth_ref: auth_ref}
      :ok = persist_connection(state, connected)

      emit_auth("jido.integration.auth.install.succeeded", %{
        auth_ref: auth_ref,
        tenant_id: session.tenant_id,
        connector_id: session.connector_id,
        auth_descriptor_id: session.auth_descriptor_id,
        auth_type: credential.type,
        state: connected.state,
        actor_id: actor_id,
        trace_id: context_value(context, :trace_id),
        span_id: context_value(context, :span_id)
      })

      {:ok, %{connection_id: connected.id, state: connected.state, auth_ref: auth_ref},
       %{
         state
         | ref_to_conn: Map.put(state.ref_to_conn, auth_ref, connected.id)
       }}
    else
      {:error, :not_found} ->
        {:error, :connection_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_transition_side_effects(new_conn, previous_conn, to_state, actor_id, opts, state) do
    unlink_credential? = to_state in [:revoked, :disabled]
    telemetry_context = Keyword.get(opts, :context, %{})

    state =
      if unlink_credential? do
        revoke_linked_credential(new_conn.auth_ref, state)
      else
        state
      end

    final_conn =
      if unlink_credential? do
        %{new_conn | auth_ref: nil}
      else
        new_conn
      end

    if to_state == :degraded and Keyword.get(opts, :reason) == :rotation_overdue do
      emit_auth("jido.integration.auth.rotation_overdue", %{
        tenant_id: final_conn.tenant_id,
        connector_id: final_conn.connector_id,
        auth_ref: previous_conn.auth_ref,
        auth_type: auth_type_for_ref(previous_conn.auth_ref, state),
        state: final_conn.state,
        actor_id: actor_id,
        trace_id: context_value(telemetry_context, :trace_id),
        span_id: context_value(telemetry_context, :span_id)
      })
    end

    {final_conn, state}
  end

  defp revoke_linked_credential(nil, state), do: state

  defp revoke_linked_credential(auth_ref, state) do
    _ = state.store_module.delete(state.store_server, auth_ref)
    %{state | ref_to_conn: Map.delete(state.ref_to_conn, auth_ref)}
  end

  defp maybe_transition_connection(auth_ref, :terminal, state) do
    with connection_id when not is_nil(connection_id) <- Map.get(state.ref_to_conn, auth_ref),
         {:ok, conn} <- fetch_connection(state, connection_id),
         {:ok, new_conn} <- Connection.transition(conn, :reauth_required, "system:refresh_failed") do
      :ok = persist_connection(state, new_conn)
      state
    else
      _ -> state
    end
  end

  defp maybe_transition_connection(_auth_ref, _failure_class, state), do: state

  defp clear_connection_auth_ref(state, connection_id) do
    case fetch_connection(state, connection_id) do
      {:ok, conn} ->
        persist_connection(state, %{conn | auth_ref: nil, updated_at: DateTime.utc_now()})

      {:error, :not_found} ->
        :ok
    end
  end

  defp emit_scope_mismatch(conn, context, missing_scopes, extra \\ []) do
    emit_auth(
      "jido.integration.auth.scope.mismatch",
      %{
        tenant_id: conn.tenant_id,
        connector_id: conn.connector_id,
        state: conn.state,
        actor_id: context_value(context, :actor_id),
        trace_id: context_value(context, :trace_id),
        span_id: context_value(context, :span_id),
        missing_scopes: missing_scopes,
        failure_class: Keyword.get(extra, :failure_class, :insufficient_scope)
      }
      |> maybe_put(:expected_connector_id, Keyword.get(extra, :expected_connector_id))
    )
  end

  defp emit_auth(event_name, metadata) do
    _ = Telemetry.emit(event_name, %{}, metadata)
    :ok
  end

  defp classify_refresh_failure(reason) do
    case normalize_failure_reason(reason) do
      "invalid_grant" -> :terminal
      "invalid_client" -> :terminal
      _ -> :retryable
    end
  end

  defp normalize_failure_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_failure_reason(reason) when is_binary(reason), do: reason
  defp normalize_failure_reason({:oauth_error, reason}), do: normalize_failure_reason(reason)
  defp normalize_failure_reason(%{error: reason}), do: normalize_failure_reason(reason)
  defp normalize_failure_reason(%{"error" => reason}), do: normalize_failure_reason(reason)
  defp normalize_failure_reason(_reason), do: "redacted"

  defp auth_type_for_ref(nil, _state), do: nil

  defp auth_type_for_ref(auth_ref, state) do
    case state.store_module.fetch(state.store_server, auth_ref, allow_expired: true) do
      {:ok, cred} -> cred.type
      {:error, :expired} -> :oauth2
      _ -> nil
    end
  end

  defp connection_state_for_ref(auth_ref, state) do
    with connection_id when not is_nil(connection_id) <- Map.get(state.ref_to_conn, auth_ref),
         {:ok, conn} <- fetch_connection(state, connection_id) do
      conn.state
    else
      _ -> nil
    end
  end

  defp fetch_connection(state, connection_id) do
    state.connection_store_module.fetch(state.connection_store_server, connection_id)
  end

  defp persist_connection(state, %Connection{} = connection) do
    state.connection_store_module.put(state.connection_store_server, connection)
  end

  defp persist_install_session(state, %InstallSession{} = session) do
    state.install_session_store_module.put(state.install_session_store_server, session)
  end

  defp load_ref_to_conn(connection_store_module, connection_store_server) do
    connection_store_module.list(connection_store_server)
    |> Enum.reduce(%{}, fn connection, acc ->
      if is_binary(connection.auth_ref) do
        Map.put(acc, connection.auth_ref, connection.id)
      else
        acc
      end
    end)
  end

  defp store_opts(opts, key), do: Keyword.get(opts, key, [])

  defp granted_scopes(params, requested_scopes) do
    granted =
      case context_value(params, :granted_scopes) || context_value(params, :scope) do
        nil -> requested_scopes
        scopes when is_list(scopes) -> scopes
        scopes when is_binary(scopes) -> String.split(scopes)
      end

    Enum.filter(granted, &(&1 in requested_scopes))
  end

  defp callback_context(params, session_state) do
    %{
      trace_id: context_value(params, :trace_id) || context_value(session_state, :trace_id),
      span_id: context_value(params, :span_id) || context_value(session_state, :span_id),
      actor_id: context_value(params, :actor_id) || context_value(session_state, :actor_id)
    }
  end

  defp context_value(context, key) when is_map(context) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp parse_connector_type("auth:" <> rest) do
    rest |> String.split(":", parts: 2) |> List.first()
  end

  defp parse_connector_type(_), do: nil

  defp connection_auth_ref(connector_id, connection_id) do
    "auth:#{connector_id}:#{connection_id}"
  end

  defp session_state_payload(%InstallSession{} = session) do
    %{
      "state" => session.state_token,
      "nonce" => session.nonce,
      "connection_id" => session.connection_id,
      "tenant_id" => session.tenant_id,
      "connector_id" => session.connector_id,
      "code_verifier" => session.code_verifier,
      "auth_descriptor_id" => session.auth_descriptor_id,
      "auth_type" => session.auth_type,
      "trace_id" => session.trace_id,
      "span_id" => session.span_id,
      "actor_id" => session.actor_id
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: Enum.into(opts, [])

  defp fetch_opt(opts, key, default \\ nil) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        value

      :error ->
        fetch_string_opt(opts, key, default)
    end
  end

  defp check_required_scopes(conn, required_scopes, context) do
    case required_scopes -- conn.scopes do
      [] ->
        :ok

      missing ->
        emit_scope_mismatch(conn, context, missing)
        {:error, %{missing_scopes: missing}}
    end
  end

  defp fetch_string_opt(opts, key, default) do
    string_key = Atom.to_string(key)

    case Enum.find(opts, fn {option_key, _value} -> option_key == string_key end) do
      {_key, value} -> value
      nil -> default
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp pkce_challenge(nil), do: nil

  defp pkce_challenge(code_verifier) do
    :crypto.hash(:sha256, code_verifier)
    |> Base.url_encode64(padding: false)
  end
end
