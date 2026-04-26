defmodule Jido.Integration.V2.RuntimeRouter do
  @moduledoc """
  Routes session and stream capabilities through the Runtime Control IR.

  Supported built-in Runtime Control driver ids are `asm` and `jido_session`. Session
  and stream capabilities must publish authored `runtime.driver`; the router
  does not synthesize an implicit default.

  Target descriptors remain compatibility and location advertisements. They do
  not override authored `runtime.driver`, `runtime.provider`, or
  `runtime.options`.

  For lower-boundary readiness, `TargetDescriptor.extensions["boundary"]`
  carries the authored baseline boundary capability advertisement. Runtime code
  may derive a runtime-merged live capability view from worker-local facts
  before boundary-backed `asm` or boundary-backed `jido_session` consumes a
  lower-boundary result.
  """

  alias Jido.Integration.V2.{Capability, Contracts, RuntimeResult, TargetDescriptor}
  alias Jido.Integration.V2.RuntimeRouter.SessionStore

  alias Jido.RuntimeControl.{
    Error,
    ExecutionResult,
    ExecutionStatus,
    RunRequest,
    Runtime,
    SessionHandle
  }

  @session_control_run_operations [:turn, :stream]
  @session_control_control_operations [:start, :status, :cancel, :approve]
  @session_control_out_of_band_operations [:status, :cancel, :approve]

  @target_driver_modules %{
    "asm" => Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriver,
    "jido_session" => Jido.Session.RuntimeControlDriver
  }
  @target_driver_ids @target_driver_modules |> Map.keys() |> Enum.sort()

  @type resolution :: %{
          driver_id: String.t(),
          driver_module: module(),
          driver_opts: keyword(),
          runtime_config: map(),
          session_key: term()
        }

  @doc """
  Starts the authored non-direct runtime boundary and its owned runtime dependencies.
  """
  @spec start!() :: :ok
  def start! do
    start_component!(Jido.Integration.V2.AsmRuntimeBridge.Application, "asm_runtime_bridge")
    start_component!(Jido.Session.Application, "jido_session")
    start_component!(Jido.Integration.V2.RuntimeRouter.Application, "runtime router")
  end

  @spec stop!() :: :ok
  def stop! do
    if pid = Process.whereis(Jido.Integration.V2.RuntimeRouter.Supervisor) do
      ref = Process.monitor(pid)
      GenServer.stop(pid, :normal)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5_000 -> raise ArgumentError, "runtime router supervisor did not stop"
      end
    else
      :ok
    end
  end

  @spec execute(Capability.t(), map(), map()) ::
          {:ok, RuntimeResult.t()} | {:error, term(), RuntimeResult.t()}
  def execute(%Capability{runtime_class: runtime_class} = capability, input, context)
      when runtime_class in [:session, :stream] and is_map(input) and is_map(context) do
    assert_started!()

    case resolve_driver(capability, input, context) do
      {:ok, resolution} ->
        case session_control_operation(capability) do
          operation when operation in @session_control_control_operations ->
            execute_session_control(operation, resolution, capability, input, context)

          operation when operation in @session_control_run_operations or is_nil(operation) ->
            execute_run_operation(resolution, capability, input, context)

          operation ->
            reason =
              Error.validation_error("Unsupported session-control operation", %{
                field: :session_control,
                value: operation,
                details: %{operation: operation}
              })

            {:error, reason, failure_runtime_result(capability, context, reason)}
        end

      {:error, reason} ->
        {:error, reason, failure_runtime_result(capability, context, reason)}
    end
  end

  defp execute_run_operation(resolution, capability, input, context) do
    case fetch_or_start_session(resolution, capability, input, context) do
      {:ok, %{session: session, lifecycle: lifecycle}} ->
        case run_driver(resolution, session, capability, input, context, lifecycle) do
          {:ok, result} ->
            finalize_execution(result, session, capability, context, lifecycle)

          {:error, reason} ->
            {:error, reason,
             failure_runtime_result(capability, context, reason, lifecycle, session.session_id)}
        end

      {:error, reason} ->
        {:error, reason, failure_runtime_result(capability, context, reason)}
    end
  end

  defp execute_session_control(:start, resolution, capability, input, context) do
    case fetch_or_start_session(resolution, capability, input, context) do
      {:ok, %{session: session, lifecycle: lifecycle}} ->
        {:ok, start_runtime_result(session, capability, lifecycle)}

      {:error, reason} ->
        {:error, reason, failure_runtime_result(capability, context, reason)}
    end
  end

  defp execute_session_control(:status, _resolution, capability, input, context) do
    with {:ok, %{driver_module: driver_module, session: session}} <-
           fetch_control_session(input, :status),
         {:ok, %ExecutionStatus{} = status} <- Runtime.session_status(driver_module, session) do
      {:ok, status_runtime_result(:status, status, session, capability)}
    else
      {:error, reason} ->
        {:error, reason,
         failure_runtime_result(capability, context, reason, nil, control_session_id(input))}
    end
  end

  defp execute_session_control(:cancel, _resolution, capability, input, context) do
    with {:ok, %{driver_module: driver_module, session: session}} <-
           fetch_control_session(input, :cancel),
         {:ok, run_id} <- required_control_string(input, :run_id, :cancel),
         :ok <- Runtime.cancel_run(driver_module, session, run_id),
         {:ok, %ExecutionStatus{} = status} <- Runtime.session_status(driver_module, session) do
      {:ok, status_runtime_result(:cancel, status, session, capability, %{run_id: run_id})}
    else
      {:error, reason} ->
        {:error, reason,
         failure_runtime_result(capability, context, reason, nil, control_session_id(input))}
    end
  end

  defp execute_session_control(:approve, _resolution, capability, input, context) do
    with {:ok, %{driver_module: driver_module, session: session}} <-
           fetch_control_session(input, :approve),
         {:ok, approval_id} <- required_control_string(input, :approval_id, :approve),
         {:ok, decision} <- required_control_decision(input),
         :ok <- Runtime.approve(driver_module, session, approval_id, decision, []),
         {:ok, %ExecutionStatus{} = status} <- Runtime.session_status(driver_module, session) do
      {:ok,
       status_runtime_result(:approve, status, session, capability, %{
         approval_id: approval_id,
         decision: decision
       })}
    else
      {:error, reason} ->
        {:error, reason,
         failure_runtime_result(capability, context, reason, nil, control_session_id(input))}
    end
  end

  @spec reset!() :: :ok
  def reset! do
    session_store_entries()
    |> Enum.each(fn {key, %{driver_module: driver_module, session: session}} ->
      _ = safe_stop_session(driver_module, session)
      delete_session_entry(key)
    end)

    reset_session_store()
    :ok
  end

  @spec available?() :: boolean()
  def available? do
    Process.whereis(SessionStore) != nil
  end

  defp assert_started! do
    if available?() do
      :ok
    else
      raise ArgumentError,
            "runtime router is not started; call Jido.Integration.V2.RuntimeRouter.start!/0 before invoking session or stream runtimes"
    end
  end

  @spec driver_modules() :: %{optional(String.t()) => module()}
  def driver_modules do
    @target_driver_modules
    |> Map.merge(configured_driver_modules())
  end

  @doc """
  Returns the only built-in Runtime Control driver ids published by the runtime boundary.
  """
  @spec target_driver_ids() :: [String.t()]
  def target_driver_ids, do: @target_driver_ids

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
    |> maybe_put(:cwd, workspace_root(context) || requested_cwd(input))
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
            {:error, {:invalid_runtime_control_session, other}}
        end
    end
  end

  defp fetch_control_session(input, operation)
       when operation in @session_control_out_of_band_operations do
    with {:ok, session_id} <- required_control_string(input, :session_id, operation) do
      case fetch_session_entry_by_id(session_id) do
        {:ok, entry} ->
          {:ok, entry}

        :error ->
          {:error,
           Error.validation_error("Runtime Control session is not active", %{
             field: :session_id,
             value: session_id,
             details: %{operation: operation}
           })}
      end
    end
  end

  defp fetch_session_entry_by_id(session_id) when is_binary(session_id) do
    session_store_entries()
    |> Enum.find_value(:error, fn
      {_key, %{session: %SessionHandle{session_id: ^session_id}} = entry} -> {:ok, entry}
      _entry -> false
    end)
  end

  defp required_control_string(input, field, operation) when is_map(input) and is_atom(field) do
    case Contracts.get(input, field) do
      value when is_binary(value) ->
        if String.trim(value) != "" do
          {:ok, value}
        else
          missing_control_field(field, value, operation)
        end

      value ->
        missing_control_field(field, value, operation)
    end
  end

  defp required_control_decision(input) when is_map(input) do
    case Contracts.get(input, :decision) do
      decision when decision in [:allow, :deny] ->
        {:ok, decision}

      "allow" ->
        {:ok, :allow}

      "deny" ->
        {:ok, :deny}

      value ->
        {:error,
         Error.validation_error("decision is required for session-control approve", %{
           field: :decision,
           value: value,
           details: %{operation: :approve}
         })}
    end
  end

  defp missing_control_field(field, value, operation) do
    {:error,
     Error.validation_error("#{field} is required for session-control #{operation}", %{
       field: field,
       value: value,
       details: %{operation: operation}
     })}
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
          {:error, {:invalid_runtime_control_execution_result, other}}
      end
    rescue
      error in [FunctionClauseError, UndefinedFunctionError, ArgumentError] ->
        {:error, {:runtime_router_invocation_failed, Exception.message(error)}}
    end
  end

  defp start_runtime_result(%SessionHandle{} = session, %Capability{} = capability, lifecycle) do
    RuntimeResult.new!(%{
      output: %{
        operation: :start,
        status: session.status,
        state: session.status,
        session_id: session.session_id,
        runtime_id: session.runtime_id,
        provider: session.provider,
        message: session_control_message(:start, session.status),
        metadata: session.metadata
      },
      runtime_ref_id: session.session_id,
      events: [
        %{
          type: lifecycle_event_type(capability.runtime_class, lifecycle),
          stream: :control,
          payload: %{
            operation: :start,
            runtime_id: session.runtime_id,
            provider: session.provider,
            status: session.status
          },
          session_id: session.session_id,
          runtime_ref_id: session.session_id
        },
        %{
          type: "session_control.started",
          stream: :control,
          payload: %{
            operation: :start,
            runtime_id: session.runtime_id,
            provider: session.provider,
            status: session.status
          },
          session_id: session.session_id,
          runtime_ref_id: session.session_id
        }
      ]
    })
  end

  defp status_runtime_result(
         operation,
         %ExecutionStatus{} = status,
         %SessionHandle{} = session,
         %Capability{} = _capability,
         extra_output \\ %{}
       ) do
    output =
      %{
        operation: operation,
        status: status.state,
        state: status.state,
        session_id: status.session_id || session.session_id,
        runtime_id: status.runtime_id,
        provider: session.provider,
        message: status.message,
        details: status.details,
        metadata: status.details
      }
      |> Map.merge(extra_output)

    RuntimeResult.new!(%{
      output: output,
      runtime_ref_id: session.session_id,
      events: [
        %{
          type: session_control_event_type(operation),
          stream: :control,
          payload: output,
          session_id: session.session_id,
          runtime_ref_id: session.session_id
        }
      ]
    })
  end

  defp session_control_event_type(:status), do: "session_control.status"
  defp session_control_event_type(:cancel), do: "session_control.cancelled"
  defp session_control_event_type(:approve), do: "session_control.approval_resolved"

  defp session_control_message(:start, :ready), do: "session ready"
  defp session_control_message(:start, state), do: "session #{state}"

  defp build_run_request(%Capability{} = capability, input, context) do
    %{
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
    }
    |> maybe_put_map(:host_tools, request_host_tools(input))
    |> maybe_put_map(:continuation, request_continuation(input))
    |> maybe_put_map(:provider_metadata, request_provider_metadata(input))
    |> RunRequest.new!()
  end

  defp request_host_tools(input) do
    case Contracts.get(input, :host_tools, []) do
      tools when is_list(tools) -> tools
      _other -> []
    end
  end

  defp request_continuation(input) do
    case Contracts.get(input, :continuation) do
      %{} = continuation -> continuation
      _other -> nil
    end
  end

  defp request_provider_metadata(input) do
    case Contracts.get(input, :provider_metadata, %{}) do
      %{} = metadata -> metadata
      _other -> %{}
    end
  end

  defp session_control_operation(%Capability{metadata: metadata}) when is_map(metadata) do
    metadata
    |> Contracts.get(:session_control)
    |> case do
      %{} = session_control ->
        raw_operation = Contracts.get(session_control, :operation)

        case normalize_session_control_operation(raw_operation) do
          nil -> {:invalid, raw_operation}
          operation -> operation
        end

      _other ->
        nil
    end
  end

  defp normalize_session_control_operation(operation) when is_atom(operation), do: operation

  defp normalize_session_control_operation(operation) when is_binary(operation) do
    operation
    |> String.trim()
    |> case do
      "approve" -> :approve
      "cancel" -> :cancel
      "start" -> :start
      "status" -> :status
      "stream" -> :stream
      "turn" -> :turn
      _other -> nil
    end
  end

  defp normalize_session_control_operation(_operation), do: nil

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
          type: runtime_control_event_type(result.status),
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
        {:runtime_control_execution_failed, status, error}

      _other ->
        {:runtime_control_execution_failed, status}
    end
  end

  defp session_key(driver_module, driver_id, capability, input, context, runtime_config) do
    target_id = context[:target_descriptor] && context.target_descriptor.target_id

    reuse_key =
      if Code.ensure_loaded?(driver_module) and function_exported?(driver_module, :reuse_key, 4) do
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

  defp control_session_id(input) when is_map(input) do
    case Contracts.get(input, :session_id) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp requested_cwd(input) when is_map(input) do
    case Contracts.get(input, :cwd) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
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

  defp runtime_control_event_type(:completed), do: "runtime_control.execution.completed"
  defp runtime_control_event_type(_status), do: "runtime_control.execution.failed"

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

  defp start_component!(application_module, label) do
    case application_module.start(:normal, []) do
      {:ok, pid} ->
        Process.unlink(pid)
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        raise ArgumentError, "failed to start #{label}: #{inspect(reason)}"
    end
  end

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

  defp session_store_entries do
    if available?() do
      SessionStore.entries()
    else
      []
    end
  catch
    :exit, {:noproc, _reason} -> []
    :exit, {{:shutdown, _reason}, _stack} -> []
    :exit, {:shutdown, _reason} -> []
  end

  defp delete_session_entry(key) do
    if available?() do
      SessionStore.delete(key)
    else
      :ok
    end
  catch
    :exit, {:noproc, _reason} -> :ok
    :exit, {{:shutdown, _reason}, _stack} -> :ok
    :exit, {:shutdown, _reason} -> :ok
  end

  defp reset_session_store do
    if available?() do
      SessionStore.reset!()
    else
      :ok
    end
  catch
    :exit, {:noproc, _reason} -> :ok
    :exit, {{:shutdown, _reason}, _stack} -> :ok
    :exit, {:shutdown, _reason} -> :ok
  end
end
