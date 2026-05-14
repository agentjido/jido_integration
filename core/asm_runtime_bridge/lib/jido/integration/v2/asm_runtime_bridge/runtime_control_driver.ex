defmodule Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriver do
  @moduledoc """
  Integration-owned `Jido.RuntimeControl.RuntimeDriver` for the authored `asm`
  runtime-driver id.

  Public Session Control handles stay pid-free; the live ASM session reference
  is stored privately in `SessionStore` and resolved by `session_id`. This
  keeps the public `jido_integration` seam at
  `jido_runtime_control` (`Jido.RuntimeControl`) while `agent_session_manager` and the
  `cli_subprocess_core` foundation remain below it.
  """

  @behaviour Jido.RuntimeControl.RuntimeDriver

  alias ASM.{Event, Provider, RuntimeAuth, Stream}
  alias Jido.Integration.V2.AsmRuntimeBridge.{Normalizer, SessionStore}
  alias Jido.Integration.V2.DynamicToolManifest
  alias Jido.Integration.V2.GovernedLowerEnvelope

  alias Jido.RuntimeControl.{
    Error,
    ExecutionStatus,
    RunHandle,
    RunRequest,
    RuntimeDescriptor,
    SessionHandle
  }

  @supported_providers [:amp, :claude, :codex, :gemini, :shell]
  @execution_surface_option_keys [
    :surface_kind,
    :transport_options,
    :lease_ref,
    :surface_ref,
    :target_id,
    :boundary_class,
    :observability
  ]
  @execution_environment_option_keys [
    :workspace_root,
    :allowed_tools,
    :approval_posture,
    :permission_mode
  ]
  @asm_session_option_keys [
    :provider,
    :execution_surface,
    :execution_environment,
    :permission_mode,
    :provider_permission_mode,
    :cli_path,
    :cwd,
    :args,
    :queue_limit,
    :overflow_policy,
    :subscriber_queue_warn,
    :subscriber_queue_limit,
    :approval_timeout_ms,
    :transport_timeout_ms,
    :transport_headless_timeout_ms,
    :max_stdout_buffer_bytes,
    :max_stderr_buffer_bytes,
    :max_concurrent_runs,
    :max_queued_runs,
    :debug,
    :driver_opts,
    :execution_mode,
    :lane,
    :stream_timeout_ms,
    :queue_timeout_ms,
    :transport_call_timeout_ms,
    :run_module,
    :run_module_opts,
    :backend_module,
    :tools,
    :tool_executor,
    :pipeline,
    :pipeline_ctx,
    :backend_opts
  ]
  @asm_run_option_keys @asm_session_option_keys ++
                         [
                           :run_id,
                           :continuation,
                           :backend_module,
                           :codex_materialized_runtime,
                           :metadata
                         ]
  @blocked_provider_option_keys [:env]

  @spec reuse_key(map(), map(), map(), map()) :: map()
  def reuse_key(capability, _input, context, runtime_config) do
    credential_ref = map_value(context, :credential_ref)
    target_descriptor = map_value(context, :target_descriptor)

    %{
      capability_id: Map.get(capability, :id),
      runtime_class: Map.get(capability, :runtime_class),
      credential_ref_id: map_value(credential_ref, :id),
      target_id:
        runtime_option_value(runtime_config, :target_id) ||
          map_value(target_descriptor, :target_id),
      provider: runtime_config_value(runtime_config, :provider),
      workspace_root:
        runtime_option_value(runtime_config, :workspace_root) || workspace_root(context),
      surface_kind: runtime_option_value(runtime_config, :surface_kind),
      # Credential leases are issued per invoke by the control plane, so they
      # cannot define stable session reuse. Only authored execution-surface
      # lease refs participate in the bridge session key.
      lease_ref: runtime_option_value(runtime_config, :lease_ref),
      surface_ref: runtime_option_value(runtime_config, :surface_ref)
    }
  end

  @impl true
  def runtime_id, do: :asm

  @impl true
  def runtime_descriptor(opts \\ []) do
    requested_provider = Keyword.get(opts, :provider)
    provider = resolve_provider(requested_provider)

    RuntimeDescriptor.new!(%{
      runtime_id: :asm,
      provider: requested_provider && Normalizer.canonical_provider(requested_provider),
      label: descriptor_label(provider),
      session_mode: :external,
      streaming?: true,
      cancellation?: true,
      approvals?: true,
      cost?: true,
      subscribe?: false,
      resume?: false,
      metadata: descriptor_metadata(provider)
    })
  end

  @impl true
  def start_session(opts) when is_list(opts) do
    assert_runtime_started!()

    with {:ok, requested_provider, provider} <- fetch_provider(opts),
         {:ok, session_ref} <-
           ASM.start_session(start_session_opts(opts, provider, requested_provider)),
         session_id when is_binary(session_id) <- ASM.session_id(session_ref) do
      :ok = SessionStore.put(session_id, session_ref)

      {:ok,
       SessionHandle.new!(%{
         session_id: session_id,
         runtime_id: :asm,
         provider: requested_provider,
         status: :ready,
         metadata:
           %{}
           |> Map.put("asm_provider", Atom.to_string(provider.name))
           |> Map.put("display_name", provider.display_name)
           |> Map.put("boundary", authored_boundary_metadata(session_id, opts))
       })}
    else
      {:error, _} = error ->
        error

      nil ->
        {:error, Error.execution_error("ASM did not return a session id", %{runtime_id: :asm})}
    end
  end

  @impl true
  def stop_session(%SessionHandle{session_id: session_id}) when is_binary(session_id) do
    assert_runtime_started!()

    result =
      case SessionStore.fetch(session_id) do
        {:ok, session_ref} ->
          ASM.stop_session(session_ref)

        :error ->
          ASM.stop_session(session_id)
      end

    :ok = SessionStore.delete(session_id)
    result
  end

  @impl true
  def stream_run(%SessionHandle{} = session, %RunRequest{} = request, opts) when is_list(opts) do
    assert_runtime_started!()

    with {:ok, provider} <- fetch_session_provider(session, opts),
         :ok <- validate_runtime_request(provider, request, opts) do
      run_id = Keyword.get_lazy(opts, :run_id, &Event.generate_id/0)
      asm_opts = stream_run_opts(request, provider, opts, run_id)

      stream =
        session
        |> session_ref!()
        |> ASM.stream(request.prompt, asm_opts)
        |> Elixir.Stream.map(&Normalizer.to_execution_event(&1, session))

      {:ok,
       RunHandle.new!(%{
         run_id: run_id,
         session_id: session.session_id,
         runtime_id: session.runtime_id,
         provider: session.provider,
         status: :running,
         started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
         metadata: %{"transport" => "stream"}
       }), stream}
    end
  rescue
    error in [ArgumentError] ->
      {:error,
       Error.execution_error(
         "ASM bridge stream_run/3 failed",
         asm_bridge_error_details(error, session, request, opts)
       )}
  end

  @impl true
  def run(%SessionHandle{} = session, %RunRequest{} = request, opts) when is_list(opts) do
    assert_runtime_started!()

    with {:ok, provider} <- fetch_session_provider(session, opts),
         :ok <- validate_runtime_request(provider, request, opts) do
      events =
        session
        |> session_ref!()
        |> ASM.stream(
          request.prompt,
          stream_run_opts(
            request,
            provider,
            opts,
            Keyword.get_lazy(opts, :run_id, &Event.generate_id/0)
          )
        )
        |> Enum.to_list()

      result = Stream.final_result(events)

      {:ok, Normalizer.to_execution_result(result, session, events)}
    end
  rescue
    error in [ArgumentError] ->
      {:error,
       Error.execution_error(
         "ASM bridge run/3 failed",
         asm_bridge_error_details(error, session, request, opts)
       )}
  end

  @impl true
  def cancel_run(%SessionHandle{} = session, %RunHandle{run_id: run_id}) do
    assert_runtime_started!()
    ASM.interrupt(session_ref!(session), run_id)
  end

  def cancel_run(%SessionHandle{} = session, run_id) when is_binary(run_id) do
    assert_runtime_started!()
    ASM.interrupt(session_ref!(session), run_id)
  end

  @impl true
  def session_status(%SessionHandle{session_id: session_id} = session)
      when is_binary(session_id) do
    assert_runtime_started!()

    health =
      case SessionStore.fetch(session_id) do
        {:ok, session_ref} -> ASM.health(session_ref)
        :error -> {:unhealthy, :not_found}
      end

    status =
      case health do
        :healthy -> :ready
        {:unhealthy, _reason} -> :stopped
      end

    message =
      case health do
        {:unhealthy, reason} -> inspect(reason)
        _ -> nil
      end

    {:ok,
     ExecutionStatus.new!(%{
       runtime_id: :asm,
       session_id: session.session_id,
       scope: :session,
       state: status,
       timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
       message: message,
       details:
         %{}
         |> maybe_put_map("provider", session.provider && Atom.to_string(session.provider))
         |> maybe_put_map("boundary", session_boundary_status_metadata(session, status))
     })}
  end

  @impl true
  def approve(%SessionHandle{} = session, approval_id, decision, _opts)
      when is_binary(approval_id) and decision in [:allow, :deny] do
    assert_runtime_started!()
    ASM.approve(session_ref!(session), approval_id, decision)
  end

  @impl true
  def cost(%SessionHandle{} = session) do
    assert_runtime_started!()
    {:ok, ASM.cost(session_ref!(session)) |> Normalizer.normalize() |> default_map()}
  end

  defp fetch_provider(opts) do
    case Keyword.fetch(opts, :provider) do
      {:ok, provider_name} when is_atom(provider_name) ->
        canonical = Normalizer.canonical_provider(provider_name)

        case Provider.resolve(canonical) do
          {:ok, provider} -> {:ok, canonical, provider}
          {:error, error} -> {:error, error}
        end

      _ ->
        {:error,
         Error.validation_error("provider is required for the ASM runtime bridge", %{
           field: :provider
         })}
    end
  end

  defp fetch_session_provider(%SessionHandle{provider: provider_name}, opts) do
    provider_name = provider_name || Keyword.get(opts, :provider)

    case provider_name do
      name when is_atom(name) ->
        case Provider.resolve(name) do
          {:ok, provider} -> {:ok, provider}
          {:error, error} -> {:error, error}
        end

      _ ->
        {:error,
         Error.validation_error("session handle is missing provider metadata", %{field: :provider})}
    end
  end

  defp resolve_provider(nil), do: nil

  defp resolve_provider(provider_name) do
    provider_name
    |> Normalizer.canonical_provider()
    |> Provider.resolve!()
  end

  defp descriptor_label(nil), do: "ASM"
  defp descriptor_label(provider), do: "#{provider.display_name} via ASM"

  defp descriptor_metadata(nil) do
    %{
      "supported_providers" => Enum.map(@supported_providers, &Atom.to_string/1)
    }
  end

  defp descriptor_metadata(provider) do
    %{
      "supported_providers" => Enum.map(@supported_providers, &Atom.to_string/1),
      "asm_provider" => Atom.to_string(provider.name),
      "display_name" => provider.display_name,
      "sdk_runtime" => provider.sdk_runtime && inspect(provider.sdk_runtime),
      "max_concurrent_runs" => provider.profile.max_concurrent_runs,
      "max_queued_runs" => provider.profile.max_queued_runs
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp authored_boundary_metadata(session_id, opts)
       when is_binary(session_id) and is_list(opts) do
    context = Keyword.get(opts, :context, %{})
    workspace_root = workspace_root_value(opts, context)
    lease_ref = lease_ref_value(opts, context)
    target_id = target_id_value(opts, context)
    surface_kind = Keyword.get(opts, :surface_kind)

    descriptor =
      %{
        "boundary_session_id" => session_id,
        "session_status" => "ready",
        "attach_state" => "attached"
      }
      |> maybe_put_map("decision_id", map_value(context, :decision_id))
      |> maybe_put_map("workspace_ref", workspace_root)
      |> maybe_put_map("lease_refs", optional_list(lease_ref))

    route =
      %{}
      |> maybe_put_map("route_id", route_id_value(context))
      |> maybe_put_map("resolved_target", resolved_target_metadata(target_id, surface_kind, opts))

    attach_grant =
      %{
        "boundary_session_id" => session_id,
        "attach_mode" => attach_mode_value(opts),
        "granted_capabilities" => allowed_tools_value(opts, context)
      }
      |> maybe_put_map("working_directory", workspace_root)
      |> maybe_put_map("attach_surface", attach_surface_metadata(surface_kind, opts))

    %{
      "descriptor" => descriptor,
      "attach_grant" => attach_grant
    }
    |> maybe_put_map("route", empty_map_to_nil(route))
  end

  defp session_boundary_status_metadata(%SessionHandle{metadata: metadata}, status)
       when is_map(metadata) do
    case Map.get(metadata, "boundary") || Map.get(metadata, :boundary) do
      %{} = boundary ->
        Map.update(
          boundary,
          "descriptor",
          %{"session_status" => Atom.to_string(status)},
          fn descriptor ->
            descriptor
            |> default_map()
            |> Map.put("session_status", Atom.to_string(status))
          end
        )

      _other ->
        nil
    end
  end

  defp session_boundary_status_metadata(_session, _status), do: nil

  defp start_session_opts(opts, provider, requested_provider) do
    opts
    |> Keyword.delete(:driver)
    |> Keyword.put(:provider, requested_provider)
    |> author_execution_inputs()
    |> Keyword.take(allowed_asm_session_option_keys(provider))
  end

  defp stream_run_opts(%RunRequest{} = request, provider, opts, run_id) do
    filtered_request_opts(request, provider)
    |> Keyword.merge(opts)
    |> normalize_bridge_run_overrides()
    |> merge_governed_lower_metadata(request)
    |> materialize_dynamic_tool_manifest(request)
    |> author_execution_inputs()
    |> Keyword.put(:run_id, run_id)
    |> Keyword.take(allowed_asm_run_option_keys(provider))
  end

  defp normalize_bridge_run_overrides(opts) do
    {run_module, opts} = Keyword.pop(opts, :driver)
    {driver_opts, opts} = Keyword.pop(opts, :driver_opts, [])

    opts =
      if is_list(driver_opts) and driver_opts != [] do
        Keyword.update(opts, :run_module_opts, driver_opts, &Keyword.merge(driver_opts, &1))
      else
        opts
      end

    case run_module do
      nil -> opts
      value -> Keyword.put(opts, :run_module, value)
    end
  end

  defp filtered_request_opts(%RunRequest{} = request, provider) do
    allowed_keys =
      provider.options_schema
      |> Keyword.keys()
      |> Kernel.--(@blocked_provider_option_keys)
      |> Enum.uniq()

    provider_opts =
      [
        model: request.model,
        max_turns: request.max_turns,
        system_prompt: request.system_prompt
      ]
      |> Keyword.merge(provider_metadata_opts(request.provider_metadata))
      |> maybe_put(:host_tools, non_empty_list_or_nil(request.host_tools))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Keyword.take(allowed_keys)

    stream_opts =
      []
      |> maybe_put(:stream_timeout_ms, request.timeout_ms)
      |> maybe_put(:cwd, request.cwd)
      |> maybe_put(:allowed_tools, request.allowed_tools)
      |> maybe_put(:continuation, normalize_continuation(request.continuation))

    provider_opts ++ stream_opts
  end

  defp validate_runtime_request(provider, %RunRequest{} = request, opts) do
    cond do
      (host_tools_requested?(request, opts) or dynamic_tool_manifest_requested?(request, opts)) and
          provider.name != :codex ->
        {:error,
         Error.validation_error(
           "host_tools are unsupported for #{provider.name}; Codex app-server is the only native host-tool lane",
           %{
             field: :host_tools,
             value: provider.name,
             details: %{provider: provider.name, capability: :host_tools}
           }
         )}

      app_server_requested?(request, opts) and provider.name != :codex ->
        {:error,
         Error.validation_error(
           "app_server is unsupported for #{provider.name}; Codex app-server is the only promoted app-server lane",
           %{
             field: :app_server,
             value: provider.name,
             details: %{provider: provider.name, capability: :app_server}
           }
         )}

      true ->
        :ok
    end
  end

  defp host_tools_requested?(%RunRequest{} = request, opts) do
    non_empty_list?(request.host_tools) or non_empty_list?(Keyword.get(opts, :host_tools))
  end

  defp dynamic_tool_manifest_requested?(%RunRequest{} = request, opts) do
    dynamic_tool_manifest(opts, request) != nil
  end

  defp app_server_requested?(%RunRequest{} = request, opts) do
    Keyword.get(opts, :app_server) == true or
      metadata_value(request.provider_metadata, :app_server) == true
  end

  defp provider_metadata_opts(metadata) when is_map(metadata) do
    Enum.reduce(metadata, [], fn {key, value}, acc ->
      case normalize_known_option_key(key) do
        nil -> acc
        normalized -> Keyword.put(acc, normalized, value)
      end
    end)
  end

  defp provider_metadata_opts(_metadata), do: []

  defp normalize_known_option_key(key) when is_atom(key), do: key

  defp normalize_known_option_key(key) when is_binary(key) do
    key
    |> String.trim()
    |> case do
      "app_server" -> :app_server
      "host_tools" -> :host_tools
      "dynamic_tools" -> :dynamic_tools
      "system_prompt" -> :system_prompt
      "model" -> :model
      "max_turns" -> :max_turns
      "skip_git_repo_check" -> :skip_git_repo_check
      _other -> nil
    end
  end

  defp normalize_known_option_key(_key), do: nil

  defp materialize_dynamic_tool_manifest(opts, %RunRequest{} = request) do
    case dynamic_tool_manifest(opts, request) do
      nil ->
        opts

      manifest ->
        context = Keyword.get(opts, :context, %{})

        resolved =
          DynamicToolManifest.resolve!(
            manifest,
            connector_manifests: Keyword.get(opts, :connector_manifests, []),
            allowed_operations: allowed_operations_value(opts, context),
            allowed_tools: allowed_tools_value(opts, context),
            authority_ref:
              Keyword.get(opts, :authority_ref) || map_value(context, :authority_ref),
            tenant_ref: Keyword.get(opts, :tenant_ref) || map_value(context, :tenant_ref),
            installation_ref:
              Keyword.get(opts, :installation_ref) || map_value(context, :installation_ref)
          )

        opts
        |> Keyword.put(
          :host_tools,
          merge_host_tools(Keyword.get(opts, :host_tools, []), resolved.host_tools)
        )
        |> Keyword.put(
          :metadata,
          merge_dynamic_tool_metadata(Keyword.get(opts, :metadata, %{}), resolved)
        )
    end
  end

  defp merge_governed_lower_metadata(opts, %RunRequest{} = request) do
    case governed_lower_envelope(opts, request) do
      nil ->
        opts

      envelope ->
        envelope_map = normalize_governed_lower_envelope!(envelope)

        opts
        |> Keyword.put(
          :metadata,
          opts
          |> Keyword.get(:metadata, %{})
          |> default_map()
          |> Map.put("governed_lower_envelope", envelope_map)
          |> Map.put("authority_metadata", authority_metadata(envelope_map))
        )
        |> put_new_from_envelope(:authority_ref, envelope_map, "authority_ref")
        |> put_new_from_envelope(:tenant_ref, envelope_map, "tenant_ref")
        |> put_new_from_envelope(:allowed_operations, envelope_map, "allowed_operations")
    end
  end

  defp governed_lower_envelope(opts, %RunRequest{} = request) do
    Keyword.get(opts, :governed_lower_envelope) ||
      metadata_value(request.provider_metadata, :governed_lower_envelope) ||
      metadata_value(request.metadata, :governed_lower_envelope)
  end

  defp normalize_governed_lower_envelope!(%GovernedLowerEnvelope{} = envelope) do
    GovernedLowerEnvelope.to_map(envelope)
  end

  defp normalize_governed_lower_envelope!(%{} = envelope) do
    envelope
    |> GovernedLowerEnvelope.new!()
    |> GovernedLowerEnvelope.to_map()
  end

  defp normalize_governed_lower_envelope!(other) do
    raise ArgumentError, "governed_lower_envelope must be a map or struct, got: #{inspect(other)}"
  end

  defp authority_metadata(envelope_map) when is_map(envelope_map) do
    Map.take(envelope_map, [
      "authority_ref",
      "authority_decision_hash",
      "capability_id",
      "action_id",
      "allowed_operations",
      "runtime_profile_ref",
      "lower_runtime_kind",
      "connector_manifest_ref",
      "connector_manifest_hash",
      "connector_manifest_state",
      "trace_id",
      "idempotency_key",
      "sandbox_profile_ref",
      "sandbox_level"
    ])
  end

  defp put_new_from_envelope(opts, key, envelope_map, envelope_key) do
    case {Keyword.has_key?(opts, key), Map.get(envelope_map, envelope_key)} do
      {false, value} when not is_nil(value) -> Keyword.put(opts, key, value)
      _other -> opts
    end
  end

  defp dynamic_tool_manifest(opts, %RunRequest{} = request) do
    Keyword.get(opts, :dynamic_tool_manifest) ||
      metadata_value(request.provider_metadata, :dynamic_tool_manifest) ||
      metadata_value(request.metadata, :dynamic_tool_manifest)
  end

  defp merge_host_tools(existing, additions) do
    List.wrap(existing) ++ List.wrap(additions)
  end

  defp merge_dynamic_tool_metadata(metadata, resolved) when is_map(metadata) do
    Map.put(metadata, "dynamic_tool_manifest", resolved.metadata)
  end

  defp merge_dynamic_tool_metadata(_metadata, resolved) do
    %{"dynamic_tool_manifest" => resolved.metadata}
  end

  defp allowed_asm_session_option_keys(provider) do
    (@asm_session_option_keys ++
       runtime_auth_option_keys() ++ allowed_provider_option_keys(provider))
    |> Enum.uniq()
  end

  defp allowed_asm_run_option_keys(provider) do
    (@asm_run_option_keys ++ runtime_auth_option_keys() ++ allowed_provider_option_keys(provider))
    |> Enum.uniq()
  end

  defp runtime_auth_option_keys do
    if Code.ensure_loaded?(RuntimeAuth) and function_exported?(RuntimeAuth, :option_keys, 0) do
      RuntimeAuth.option_keys()
    else
      []
    end
  end

  defp allowed_provider_option_keys(provider) do
    provider.options_schema
    |> Keyword.keys()
    |> Kernel.--(@blocked_provider_option_keys)
  end

  defp normalize_continuation(nil), do: nil

  defp normalize_continuation(%{} = continuation) do
    strategy = metadata_value(continuation, :strategy)
    provider_session_id = metadata_value(continuation, :provider_session_id)

    cond do
      strategy in [:exact, "exact"] and is_binary(provider_session_id) and
          provider_session_id != "" ->
        %{strategy: :exact, provider_session_id: provider_session_id}

      strategy in [:latest, "latest"] ->
        %{strategy: :latest}

      true ->
        continuation
    end
  end

  defp normalize_continuation(other), do: other

  defp metadata_value(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp metadata_value(_map, _key), do: nil

  defp non_empty_list_or_nil(value) when is_list(value) and value != [], do: value
  defp non_empty_list_or_nil(_value), do: nil

  defp non_empty_list?(value), do: is_list(value) and value != []

  defp author_execution_inputs(opts) when is_list(opts) do
    context = Keyword.get(opts, :context, %{})
    approval_posture = approval_posture_value(opts, context)

    execution_surface =
      Keyword.get(opts, :execution_surface) || authored_execution_surface(opts, context)

    execution_environment =
      Keyword.get(opts, :execution_environment) ||
        authored_execution_environment(opts, context, approval_posture)

    opts
    |> Keyword.delete(:provider_permission_mode)
    |> Keyword.drop(@execution_surface_option_keys ++ @execution_environment_option_keys)
    |> maybe_put(:execution_surface, execution_surface)
    |> maybe_put(:execution_environment, execution_environment)
  end

  defp authored_execution_surface(opts, context) when is_list(opts) do
    []
    |> maybe_put(:surface_kind, Keyword.get(opts, :surface_kind))
    |> maybe_put(:transport_options, Keyword.get(opts, :transport_options))
    |> maybe_put(:lease_ref, lease_ref_value(opts, context))
    |> maybe_put(:surface_ref, Keyword.get(opts, :surface_ref))
    |> maybe_put(:target_id, target_id_value(opts, context))
    |> maybe_put(:boundary_class, Keyword.get(opts, :boundary_class))
    |> maybe_put(:observability, Keyword.get(opts, :observability))
    |> empty_keyword_to_nil()
  end

  defp authored_execution_environment(opts, context, approval_posture) when is_list(opts) do
    []
    |> maybe_put(:workspace_root, workspace_root_value(opts, context))
    |> maybe_put(:allowed_tools, allowed_tools_value(opts, context))
    |> maybe_put(:approval_posture, approval_posture)
    |> maybe_put(:permission_mode, permission_mode_value(opts))
    |> empty_keyword_to_nil()
  end

  defp session_ref!(%SessionHandle{session_id: session_id}) when is_binary(session_id) do
    case SessionStore.fetch(session_id) do
      {:ok, session_ref} ->
        session_ref

      :error ->
        raise ArgumentError, "ASM session reference is not available for #{inspect(session_id)}"
    end
  end

  defp workspace_root(context) do
    target_descriptor = map_value(context, :target_descriptor)
    target_location = map_value(target_descriptor, :location)
    policy_inputs = map_value(context, :policy_inputs)
    execution = map_value(policy_inputs, :execution)
    sandbox = map_value(execution, :sandbox)

    map_value(target_location, :workspace_root) || map_value(sandbox, :file_scope)
  end

  defp workspace_root_value(opts, context) do
    Keyword.get(opts, :workspace_root) || workspace_root(context)
  end

  defp allowed_tools_value(opts, context) do
    if Keyword.has_key?(opts, :allowed_tools) do
      Keyword.get(opts, :allowed_tools)
    else
      allowed_tools(context)
    end
  end

  defp allowed_operations_value(opts, context) do
    Keyword.get(opts, :allowed_operations) ||
      get_in(context, [:policy_inputs, :execution, :operations, :allowed_operations]) ||
      get_in(context, [:policy_inputs, :execution, "operations", "allowed_operations"]) ||
      get_in(context, ["policy_inputs", "execution", "operations", "allowed_operations"]) ||
      []
  end

  defp approval_posture_value(opts, context) do
    cond do
      Keyword.has_key?(opts, :approval_posture) ->
        Keyword.get(opts, :approval_posture)

      Keyword.has_key?(opts, :approval_mode) ->
        Keyword.get(opts, :approval_mode)

      true ->
        get_in(context, [:policy_inputs, :execution, :sandbox, :approvals])
    end
  end

  defp permission_mode_value(opts) do
    if Keyword.has_key?(opts, :permission_mode) do
      Keyword.get(opts, :permission_mode)
    else
      nil
    end
  end

  defp lease_ref_value(opts, context) do
    Keyword.get(opts, :lease_ref) || credential_lease_ref(context)
  end

  defp target_id_value(opts, context) do
    Keyword.get(opts, :target_id) || map_value(map_value(context, :target_descriptor), :target_id)
  end

  defp allowed_tools(context) do
    get_in(context, [:policy_inputs, :execution, :sandbox, :allowed_tools]) || []
  end

  defp credential_lease_ref(context) do
    context
    |> map_value(:credential_lease)
    |> map_value(:lease_id)
  end

  defp runtime_config_value(runtime_config, key) when is_map(runtime_config) do
    Map.get(runtime_config, key) || Map.get(runtime_config, Atom.to_string(key))
  end

  defp runtime_config_value(_runtime_config, _key), do: nil

  defp runtime_option_value(runtime_config, key) when is_map(runtime_config) do
    options = runtime_config_value(runtime_config, :options)

    cond do
      not is_nil(map_value(options, key)) ->
        map_value(options, key)

      key in @execution_surface_option_keys ->
        map_value(map_value(options, :execution_surface), key)

      key in @execution_environment_option_keys ->
        map_value(map_value(options, :execution_environment), key)

      true ->
        runtime_config_value(runtime_config, key)
    end
  end

  defp runtime_option_value(_runtime_config, _key), do: nil

  defp route_id_value(context) do
    map_value(map_value(context, :route), :route_id)
  end

  defp resolved_target_metadata(target_id, surface_kind, opts) do
    %{}
    |> maybe_put_map("target_id", target_id)
    |> maybe_put_map("surface_ref", Keyword.get(opts, :surface_ref))
    |> maybe_put_map("surface_kind", surface_kind && Atom.to_string(surface_kind))
    |> empty_map_to_nil()
  end

  defp attach_surface_metadata(surface_kind, opts) do
    %{}
    |> maybe_put_map("surface_kind", surface_kind && Atom.to_string(surface_kind))
    |> maybe_put_map("surface_ref", Keyword.get(opts, :surface_ref))
    |> maybe_put_map("target_id", Keyword.get(opts, :target_id))
    |> empty_map_to_nil()
  end

  defp attach_mode_value(opts) do
    case Keyword.get(opts, :permission_mode) do
      :plan -> "read_only"
      :bypass -> "read_write"
      nil -> "read_write"
      other -> to_string(other)
    end
  end

  defp optional_list(nil), do: nil
  defp optional_list(value), do: [value]

  defp empty_keyword_to_nil([]), do: nil
  defp empty_keyword_to_nil(keyword), do: keyword
  defp empty_map_to_nil(map) when map == %{}, do: nil
  defp empty_map_to_nil(map), do: map

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_map(map, _key, nil), do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, value)

  defp default_map(%{} = value), do: value
  defp default_map(_other), do: %{}

  defp map_value(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(keyword, key) when is_list(keyword), do: Keyword.get(keyword, key)
  defp map_value(_other, _key), do: nil

  defp asm_bridge_error_details(error, %SessionHandle{} = session, %RunRequest{} = request, opts) do
    message = Exception.message(error)

    details = %{error: message}

    case host_tool_incident(message, session, request, opts) do
      nil -> details
      incident -> Map.put(details, :host_tool_incident, incident)
    end
  end

  defp host_tool_incident(message, %SessionHandle{} = session, %RunRequest{} = request, opts) do
    manifest = dynamic_tool_manifest(opts, request)

    cond do
      is_nil(manifest) ->
        nil

      not String.contains?(message, "dynamic host tool") and
          not String.contains?(message, "dynamic tool") ->
        nil

      true ->
        context = Keyword.get(opts, :context, %{})

        %{
          incident_type: "host_tool_denial",
          stage: "dynamic_tool_manifest_resolution",
          provider: session.provider && Atom.to_string(session.provider),
          run_id: Keyword.get(opts, :run_id),
          authority_ref: Keyword.get(opts, :authority_ref) || map_value(context, :authority_ref),
          tenant_ref: Keyword.get(opts, :tenant_ref) || map_value(context, :tenant_ref),
          installation_ref:
            Keyword.get(opts, :installation_ref) || map_value(context, :installation_ref),
          requested_manifest: normalize_incident_manifest(manifest),
          reason: message
        }
        |> drop_nil_values()
    end
  end

  defp normalize_incident_manifest(%{} = manifest) do
    Map.new(manifest, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp normalize_incident_manifest(other), do: other

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp assert_runtime_started! do
    if Process.whereis(SessionStore) do
      :ok
    else
      raise ArgumentError,
            "asm_runtime_bridge session store is not started; start Jido.Integration.V2.AsmRuntimeBridge.Application before using the ASM bridge runtime"
    end
  end
end
