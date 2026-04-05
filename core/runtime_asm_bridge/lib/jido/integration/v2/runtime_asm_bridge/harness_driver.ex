defmodule Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver do
  @moduledoc """
  Integration-owned `Jido.Harness.RuntimeDriver` for the authored `asm`
  runtime-driver id.

  Public Session Control handles stay pid-free; the live ASM session reference
  is stored privately in `SessionStore` and resolved by `session_id`. This
  keeps the public `jido_integration` seam at
  `/home/home/p/g/n/jido_harness` (`Jido.Harness`) while
  `/home/home/p/g/n/agent_session_manager` and the
  `/home/home/p/g/n/cli_subprocess_core` foundation remain below it.
  """

  @behaviour Jido.Harness.RuntimeDriver

  alias ASM.{Event, Provider, Stream}
  alias Jido.Integration.V2.RuntimeAsmBridge.{Normalizer, SessionStore}

  alias Jido.Harness.{
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
    :env,
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
    :stream_timeout_ms,
    :queue_timeout_ms,
    :transport_call_timeout_ms,
    :run_module,
    :run_module_opts,
    :tools,
    :tool_executor,
    :pipeline,
    :pipeline_ctx
  ]
  @asm_run_option_keys @asm_session_option_keys ++ [:run_id]

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
    with {:ok, provider} <- fetch_session_provider(session, opts) do
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
       Error.execution_error("ASM bridge stream_run/3 failed", %{error: Exception.message(error)})}
  end

  @impl true
  def run(%SessionHandle{} = session, %RunRequest{} = request, opts) when is_list(opts) do
    with {:ok, provider} <- fetch_session_provider(session, opts) do
      result =
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
        |> Stream.final_result()

      {:ok, Normalizer.to_execution_result(result, session)}
    end
  rescue
    error in [ArgumentError] ->
      {:error,
       Error.execution_error("ASM bridge run/3 failed", %{error: Exception.message(error)})}
  end

  @impl true
  def cancel_run(%SessionHandle{} = session, %RunHandle{run_id: run_id}) do
    ASM.interrupt(session_ref!(session), run_id)
  end

  def cancel_run(%SessionHandle{} = session, run_id) when is_binary(run_id) do
    ASM.interrupt(session_ref!(session), run_id)
  end

  @impl true
  def session_status(%SessionHandle{session_id: session_id} = session)
      when is_binary(session_id) do
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
     })}
  end

  @impl true
  def approve(%SessionHandle{} = session, approval_id, decision, _opts)
      when is_binary(approval_id) and decision in [:allow, :deny] do
    ASM.approve(session_ref!(session), approval_id, decision)
  end

  @impl true
  def cost(%SessionHandle{} = session) do
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

  defp start_session_opts(opts, provider, requested_provider) do
    opts
    |> Keyword.delete(:driver)
    |> Keyword.put(:provider, requested_provider)
    |> author_execution_inputs()
    |> Keyword.take(@asm_session_option_keys ++ Keyword.keys(provider.options_schema))
  end

  defp stream_run_opts(%RunRequest{} = request, provider, opts, run_id) do
    filtered_request_opts(request, provider)
    |> Keyword.merge(opts)
    |> normalize_bridge_run_overrides()
    |> author_execution_inputs()
    |> Keyword.put(:run_id, run_id)
    |> Keyword.take(@asm_run_option_keys ++ Keyword.keys(provider.options_schema))
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
      |> Enum.uniq()

    provider_opts =
      [
        model: request.model,
        max_turns: request.max_turns,
        system_prompt: request.system_prompt
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Keyword.take(allowed_keys)

    stream_opts =
      []
      |> maybe_put(:stream_timeout_ms, request.timeout_ms)
      |> maybe_put(:cwd, request.cwd)
      |> maybe_put(:allowed_tools, request.allowed_tools)

    provider_opts ++ stream_opts
  end

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

  defp empty_keyword_to_nil([]), do: nil
  defp empty_keyword_to_nil(keyword), do: keyword

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
end
