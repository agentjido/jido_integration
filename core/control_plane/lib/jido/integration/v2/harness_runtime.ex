defmodule Jido.Integration.V2.HarnessRuntime do
  @moduledoc """
  Routes session and stream capabilities through the Harness Session Control IR.

  Target Harness driver ids for new architecture work are `asm` and
  `jido_session`. The integration-owned bridge ids remain available only as
  compatibility shims while older fixtures are retired. Session and stream
  capabilities must publish authored `runtime.driver`; the router does not
  synthesize an implicit default.

  Target descriptors remain compatibility and location advertisements. They do
  not override authored `runtime.driver`, `runtime.provider`, or
  `runtime.options`.
  """

  alias Jido.Harness.{ExecutionResult, RunRequest, SessionHandle}
  alias Jido.Integration.V2.{Capability, Contracts, RuntimeResult, TargetDescriptor}
  alias Jido.Integration.V2.HarnessRuntime.SessionStore

  @target_driver_modules %{
    "asm" => Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver,
    "jido_session" => Jido.Session.HarnessDriver
  }

  @compatibility_driver_modules %{
    "integration_session_bridge" => Jido.Integration.V2.SessionKernel.HarnessDriver,
    "integration_stream_bridge" => Jido.Integration.V2.StreamRuntime.HarnessDriver
  }
  @target_driver_ids @target_driver_modules |> Map.keys() |> Enum.sort()
  @compatibility_driver_ids @compatibility_driver_modules |> Map.keys() |> Enum.sort()

  @type resolution :: %{
          driver_id: String.t(),
          driver_module: module(),
          driver_opts: keyword(),
          runtime_config: map(),
          session_key: term()
        }

  @spec execute(Capability.t(), map(), map()) ::
          {:ok, RuntimeResult.t()} | {:error, term(), RuntimeResult.t()}
  def execute(%Capability{runtime_class: runtime_class} = capability, input, context)
      when runtime_class in [:session, :stream] and is_map(input) and is_map(context) do
    with {:ok, resolution} <- resolve_driver(capability, input, context),
         {:ok, %{session: session, lifecycle: lifecycle}} <-
           fetch_or_start_session(resolution, capability, input, context) do
      case run_driver(resolution, session, capability, input, context, lifecycle) do
        {:ok, result} ->
          finalize_execution(result, session, capability, context, lifecycle)

        {:error, reason} ->
          {:error, reason,
           failure_runtime_result(capability, context, reason, lifecycle, session.session_id)}
      end
    else
      {:error, reason} ->
        {:error, reason, failure_runtime_result(capability, context, reason)}
    end
  end

  @spec reset!() :: :ok
  def reset! do
    Enum.each(SessionStore.entries(), fn {key, %{driver_module: driver_module, session: session}} ->
      _ = safe_stop_session(driver_module, session)
      SessionStore.delete(key)
    end)

    SessionStore.reset!()
  end

  @spec driver_modules() :: %{optional(String.t()) => module()}
  def driver_modules do
    @target_driver_modules
    |> Map.merge(@compatibility_driver_modules)
    |> Map.merge(configured_driver_modules())
  end

  @doc """
  Returns the only Harness driver ids that new runtime-boundary work should target.
  """
  @spec target_driver_ids() :: [String.t()]
  def target_driver_ids, do: @target_driver_ids

  @doc """
  Returns the legacy bridge driver ids that remain for compatibility only.
  """
  @spec compatibility_driver_ids() :: [String.t()]
  def compatibility_driver_ids, do: @compatibility_driver_ids

  @spec driver_module(atom() | String.t()) :: {:ok, module()} | :error
  def driver_module(driver_id) when is_atom(driver_id) or is_binary(driver_id) do
    Map.fetch(driver_modules(), normalize_driver_id(driver_id))
  end

  defp resolve_driver(capability, input, context) do
    runtime_config = authored_runtime_config(capability)

    case Contracts.get(runtime_config, :driver) do
      nil ->
        {:error, {:missing_runtime_driver, capability.runtime_class}}

      driver_value ->
        with {:ok, driver_id, driver_module} <- resolve_driver_module(driver_value) do
          resolution = %{
            driver_id: driver_id,
            driver_module: driver_module,
            runtime_config: runtime_config,
            driver_opts: driver_opts(runtime_config, capability, input, context),
            session_key:
              session_key(driver_module, driver_id, capability, input, context, runtime_config)
          }

          {:ok, resolution}
        end
    end
  end

  defp authored_runtime_config(%Capability{metadata: metadata}) do
    capability_config =
      case Contracts.get(metadata, :runtime, %{}) do
        value when is_map(value) -> normalize_runtime_config(value)
        _other -> %{}
      end

    capability_config
  end

  defp resolve_driver_module(driver_value) when is_atom(driver_value) do
    driver_id = Atom.to_string(driver_value)

    case Map.fetch(driver_modules(), driver_id) do
      {:ok, module} -> {:ok, driver_id, module}
      :error -> {:error, {:unknown_runtime_driver, driver_value}}
    end
  end

  defp resolve_driver_module(driver_value) when is_binary(driver_value) do
    case Map.fetch(driver_modules(), driver_value) do
      {:ok, module} -> {:ok, driver_value, module}
      :error -> {:error, {:unknown_runtime_driver, driver_value}}
    end
  end

  defp resolve_driver_module(driver_value) do
    {:error, {:invalid_runtime_driver, driver_value}}
  end

  defp driver_opts(runtime_config, capability, input, context) do
    options =
      runtime_config
      |> Contracts.get(:options, %{})
      |> map_to_keyword()
      |> normalize_driver_option_aliases()

    options
    |> maybe_put(:provider, normalize_optional_atom(Contracts.get(runtime_config, :provider)))
    |> maybe_put(:cwd, workspace_root(context))
    |> maybe_put(:allowed_tools, allowed_tools(context))
    |> Keyword.put(:capability, capability)
    |> Keyword.put(:input, input)
    |> Keyword.put(:context, context)
    |> Keyword.put_new(:run_id, context.run_id)
  end

  defp fetch_or_start_session(
         %{driver_module: driver_module, driver_opts: driver_opts, session_key: session_key},
         _capability,
         _input,
         _context
       ) do
    case SessionStore.fetch(session_key) do
      {:ok, %{session: %SessionHandle{} = session}} ->
        {:ok, %{session: session, lifecycle: :reused}}

      :error ->
        case driver_module.start_session(driver_opts) do
          {:ok, %SessionHandle{} = session} ->
            SessionStore.put(session_key, %{driver_module: driver_module, session: session})
            {:ok, %{session: session, lifecycle: :started}}

          {:error, _reason} = error ->
            error

          other ->
            {:error, {:invalid_harness_session, other}}
        end
    end
  end

  defp run_driver(
         %{driver_module: driver_module, driver_opts: driver_opts},
         %SessionHandle{} = session,
         capability,
         input,
         context,
         lifecycle
       ) do
    request = build_run_request(capability, input, context)

    run_opts =
      Keyword.merge(driver_opts,
        capability: capability,
        input: input,
        context: context,
        lifecycle: lifecycle
      )

    try do
      case driver_module.run(session, request, run_opts) do
        {:ok, %ExecutionResult{} = result} ->
          {:ok, result}

        {:error, _reason} = error ->
          error

        other ->
          {:error, {:invalid_harness_execution_result, other}}
      end
    rescue
      error in [FunctionClauseError, UndefinedFunctionError, ArgumentError] ->
        {:error, {:harness_runtime_invocation_failed, Exception.message(error)}}
    end
  end

  defp build_run_request(%Capability{} = capability, input, context) do
    RunRequest.new!(%{
      prompt: request_prompt(capability, input),
      cwd: workspace_root(context),
      allowed_tools: allowed_tools(context),
      metadata: %{
        "capability_id" => capability.id,
        "run_id" => context.run_id,
        "attempt_id" => context.attempt_id,
        "runtime_class" => Atom.to_string(capability.runtime_class),
        "target_id" => context[:target_descriptor] && context.target_descriptor.target_id,
        "input" => input
      }
    })
  end

  defp finalize_execution(
         %ExecutionResult{} = result,
         %SessionHandle{} = session,
         %Capability{} = capability,
         context,
         lifecycle
       ) do
    runtime_result =
      case embedded_runtime_result(result) do
        %RuntimeResult{} = runtime_result ->
          decorate_runtime_result(runtime_result, session.session_id)

        nil ->
          synthesized_runtime_result(result, session, capability, lifecycle)
      end

    if result.status == :completed do
      {:ok, runtime_result}
    else
      {:error, failure_reason(result, context), runtime_result}
    end
  end

  defp synthesized_runtime_result(
         %ExecutionResult{} = result,
         %SessionHandle{session_id: session_id},
         %Capability{} = capability,
         lifecycle
       ) do
    RuntimeResult.new!(%{
      output:
        %{}
        |> maybe_put_map(:text, result.text)
        |> maybe_put_map(:status, result.status)
        |> maybe_put_map(:runtime_id, result.runtime_id)
        |> maybe_put_map(:provider, result.provider)
        |> maybe_put_map(:messages, result.messages)
        |> maybe_put_map(:stop_reason, result.stop_reason)
        |> maybe_put_map(:metadata, result.metadata),
      runtime_ref_id: session_id,
      events: [
        %{
          type: "attempt.started",
          payload: %{capability_id: capability.id},
          session_id: session_id,
          runtime_ref_id: session_id
        },
        %{
          type: lifecycle_event_type(capability.runtime_class, lifecycle),
          payload: %{
            runtime_id: result.runtime_id,
            provider: result.provider
          },
          session_id: session_id,
          runtime_ref_id: session_id
        },
        %{
          type: harness_event_type(result.status),
          stream: :control,
          payload: %{
            runtime_id: result.runtime_id,
            provider: result.provider,
            status: result.status,
            text: result.text
          },
          session_id: session_id,
          runtime_ref_id: session_id
        },
        %{
          type: completion_event_type(result.status),
          payload: %{
            runtime_id: result.runtime_id,
            provider: result.provider
          },
          session_id: session_id,
          runtime_ref_id: session_id
        }
      ]
    })
  end

  defp decorate_runtime_result(%RuntimeResult{} = runtime_result, session_id) do
    %RuntimeResult{
      runtime_result
      | runtime_ref_id: runtime_result.runtime_ref_id || session_id,
        events:
          Enum.map(runtime_result.events, fn event ->
            event
            |> Map.put_new(:session_id, session_id)
            |> Map.put_new(:runtime_ref_id, runtime_result.runtime_ref_id || session_id)
          end)
    }
  end

  defp failure_runtime_result(
         %Capability{} = capability,
         _context,
         reason,
         lifecycle \\ nil,
         session_id \\ nil
       ) do
    events =
      [
        %{
          type: "attempt.started",
          payload: %{capability_id: capability.id},
          session_id: session_id,
          runtime_ref_id: session_id
        }
      ]
      |> maybe_append_lifecycle_event(capability.runtime_class, lifecycle, session_id)
      |> Kernel.++([
        %{
          type: "attempt.failed",
          payload: %{reason: inspect(reason)},
          session_id: session_id,
          runtime_ref_id: session_id
        }
      ])

    RuntimeResult.new!(%{
      output: nil,
      runtime_ref_id: session_id,
      events: events
    })
  end

  defp embedded_runtime_result(%ExecutionResult{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "jido_integration") || Map.get(metadata, :jido_integration) do
      %{"runtime_result" => %RuntimeResult{} = runtime_result} ->
        runtime_result

      %{runtime_result: %RuntimeResult{} = runtime_result} ->
        runtime_result

      _other ->
        nil
    end
  end

  defp failure_reason(
         %ExecutionResult{metadata: metadata, error: error, status: status},
         _context
       )
       when is_map(metadata) do
    case Map.get(metadata, "jido_integration") || Map.get(metadata, :jido_integration) do
      %{"failure_reason" => reason} ->
        reason

      %{failure_reason: reason} ->
        reason

      _other when not is_nil(error) ->
        {:harness_execution_failed, status, error}

      _other ->
        {:harness_execution_failed, status}
    end
  end

  defp session_key(driver_module, driver_id, capability, input, context, runtime_config) do
    target_id = context[:target_descriptor] && context.target_descriptor.target_id

    reuse_key =
      if function_exported?(driver_module, :reuse_key, 4) do
        driver_module.reuse_key(capability, input, context, runtime_config)
      else
        %{
          capability_id: capability.id,
          runtime_class: capability.runtime_class,
          credential_ref_id: context.credential_ref.id,
          target_id: target_id,
          provider: Contracts.get(runtime_config, :provider),
          workspace_root: workspace_root(context)
        }
      end

    {driver_id, reuse_key}
  end

  defp request_prompt(%Capability{id: capability_id}, input) do
    case Contracts.get(input, :prompt) do
      prompt when is_binary(prompt) and prompt != "" ->
        prompt

      _other ->
        "#{capability_id}: #{inspect(input)}"
    end
  end

  defp workspace_root(context) do
    if match?(%TargetDescriptor{}, context[:target_descriptor]) do
      Contracts.get(context.target_descriptor.location, :workspace_root)
    else
      get_in(context, [:policy_inputs, :execution, :sandbox, :file_scope])
    end
  end

  defp allowed_tools(context) do
    get_in(context, [:policy_inputs, :execution, :sandbox, :allowed_tools]) || []
  end

  defp maybe_append_lifecycle_event(events, _runtime_class, nil, _session_id), do: events

  defp maybe_append_lifecycle_event(events, runtime_class, lifecycle, session_id) do
    events ++
      [
        %{
          type: lifecycle_event_type(runtime_class, lifecycle),
          payload: %{},
          session_id: session_id,
          runtime_ref_id: session_id
        }
      ]
  end

  defp lifecycle_event_type(:session, :started), do: "session.started"
  defp lifecycle_event_type(:session, :reused), do: "session.reused"
  defp lifecycle_event_type(:stream, :started), do: "stream.started"
  defp lifecycle_event_type(:stream, :reused), do: "stream.reused"

  defp harness_event_type(:completed), do: "harness.execution.completed"
  defp harness_event_type(_status), do: "harness.execution.failed"

  defp completion_event_type(:completed), do: "attempt.completed"
  defp completion_event_type(_status), do: "attempt.failed"

  defp map_to_keyword(map) when is_map(map) do
    Enum.reduce(map, [], fn
      {key, value}, acc when is_atom(key) ->
        Keyword.put(acc, key, value)

      {key, value}, acc when is_binary(key) and byte_size(key) > 0 ->
        Keyword.put(acc, String.to_atom(key), value)

      {_key, _value}, acc ->
        acc
    end)
  end

  defp map_to_keyword(_other), do: []

  defp normalize_runtime_config(config) when is_map(config) do
    %{}
    |> maybe_put_map(:driver, Contracts.get(config, :driver))
    |> maybe_put_map(:provider, Contracts.get(config, :provider))
    |> Map.put(:options, normalize_runtime_options(Contracts.get(config, :options, %{})))
  end

  defp normalize_runtime_options(options) when is_map(options), do: options
  defp normalize_runtime_options(_other), do: %{}

  defp normalize_driver_option_aliases(opts) do
    case Keyword.pop(opts, :driver_module) do
      {nil, opts} -> opts
      {driver_module, opts} -> Keyword.put(opts, :driver, driver_module)
    end
  end

  defp normalize_optional_atom(nil), do: nil
  defp normalize_optional_atom(value) when is_atom(value), do: value
  defp normalize_optional_atom(value) when is_binary(value), do: String.to_atom(value)

  defp configured_driver_modules do
    :jido_integration_v2_control_plane
    |> Application.get_env(:runtime_drivers, %{})
    |> Enum.reduce(%{}, fn
      {driver_id, module}, acc when is_atom(driver_id) and is_atom(module) ->
        Map.put(acc, Atom.to_string(driver_id), module)

      {driver_id, module}, acc when is_binary(driver_id) and is_atom(module) ->
        Map.put(acc, driver_id, module)

      _, acc ->
        acc
    end)
  end

  defp normalize_driver_id(driver_id) when is_atom(driver_id), do: Atom.to_string(driver_id)
  defp normalize_driver_id(driver_id) when is_binary(driver_id), do: driver_id

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put_new(opts, key, value)

  defp maybe_put_map(map, _key, nil), do: map
  defp maybe_put_map(map, _key, []), do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, value)

  defp safe_stop_session(driver_module, session) do
    driver_module.stop_session(session)
  rescue
    _error -> :ok
  end
end
