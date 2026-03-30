defmodule Jido.Session do
  @moduledoc """
  Internal Jido-native session runtime with a small deterministic first session type.

  `Jido.Session` owns the internal session kernel for app-controlled execution and
  projects its state through the Harness Session Control IR via
  `Jido.Session.HarnessDriver`.

  When lower-boundary execution is introduced, `jido_session` stays on the
  same authored Harness seam as `asm`. Target descriptors advertise the
  authored baseline boundary capability, and runtime code may merge
  worker-local facts into a runtime-merged live capability view before a
  boundary-backed `jido_session` consumes a lower-boundary result.
  """

  alias Jido.BoundaryBridge

  alias Jido.Harness.{
    Error,
    ExecutionResult,
    ExecutionStatus,
    RunHandle,
    RunRequest,
    SessionHandle
  }

  alias Jido.Session.{HarnessProjection, Store}
  alias Jido.Session.Runtime.{LocalEcho, Run, Session}

  @runtime_id :jido_session

  @type session_record :: Session.t()
  @type run_record :: Run.t()

  @doc "Returns the runtime id published to Harness."
  @spec runtime_id() :: atom()
  def runtime_id, do: @runtime_id

  @doc "Returns the Harness runtime descriptor for this runtime."
  @spec runtime_descriptor(keyword()) :: Jido.Harness.RuntimeDescriptor.t()
  def runtime_descriptor(opts \\ []), do: HarnessProjection.runtime_descriptor(opts)

  @doc "Starts a new internal session and returns its Session Control handle."
  @spec start_session(keyword()) :: {:ok, SessionHandle.t()} | {:error, term()}
  def start_session(opts \\ []) when is_list(opts) do
    with {:ok, boundary} <- maybe_prepare_boundary(opts),
         session <- build_session(opts, boundary),
         :ok <- Store.put_session(session) do
      {:ok, HarnessProjection.session_handle(session)}
    end
  end

  @doc "Stops an internal session."
  @spec stop_session(SessionHandle.t()) :: :ok
  def stop_session(%SessionHandle{session_id: session_id}) do
    case Store.delete_session(session_id) do
      {:ok, _session} -> :ok
      {:error, :not_found} -> :ok
    end
  end

  @doc "Fetches the richer internal session record."
  @spec fetch_session(String.t()) :: {:ok, session_record()} | {:error, :not_found}
  def fetch_session(session_id) when is_binary(session_id), do: Store.fetch_session(session_id)

  @doc "Fetches the richer internal run record."
  @spec fetch_run(String.t()) :: {:ok, run_record()} | {:error, :not_found}
  def fetch_run(run_id) when is_binary(run_id), do: Store.fetch_run(run_id)

  @doc "Projects session status through the Harness Session Control IR."
  @spec session_status(SessionHandle.t()) :: {:ok, ExecutionStatus.t()} | {:error, term()}
  def session_status(%SessionHandle{session_id: session_id}) do
    with {:ok, %Session{} = session} <- Store.fetch_session(session_id) do
      {:ok, HarnessProjection.session_status(session)}
    end
  end

  @doc "Runs a deterministic streaming execution and returns projected IR events."
  @spec stream_run(SessionHandle.t(), RunRequest.t(), keyword()) ::
          {:ok, RunHandle.t(), Enumerable.t(Jido.Harness.ExecutionEvent.t())} | {:error, term()}
  def stream_run(%SessionHandle{session_id: session_id}, %RunRequest{} = request, opts \\ []) do
    with {:ok, %Session{} = session} <- Store.fetch_session(session_id),
         {:ok, started_run, completed_run} <- execute_run(session, request, opts),
         :ok <- persist_run(session, completed_run) do
      {:ok, HarnessProjection.run_handle(started_run),
       HarnessProjection.events(session, completed_run)}
    end
  end

  @doc "Runs a deterministic execution and returns the projected terminal result."
  @spec run(SessionHandle.t(), RunRequest.t(), keyword()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def run(%SessionHandle{session_id: session_id}, %RunRequest{} = request, opts \\ []) do
    with {:ok, %Session{} = session} <- Store.fetch_session(session_id),
         {:ok, _started_run, completed_run} <- execute_run(session, request, opts),
         :ok <- persist_run(session, completed_run) do
      {:ok, HarnessProjection.result(session, completed_run)}
    end
  end

  @doc "Cancels a stored run by id or handle."
  @spec cancel_run(SessionHandle.t(), RunHandle.t() | String.t()) ::
          :ok | {:error, :run_session_mismatch}
  def cancel_run(%SessionHandle{} = session, %RunHandle{run_id: run_id}),
    do: cancel_run(session, run_id)

  def cancel_run(%SessionHandle{session_id: session_id}, run_id) when is_binary(run_id) do
    with {:ok, %Run{} = run} <- Store.fetch_run(run_id),
         true <- run.session_id == session_id do
      :ok = Store.put_run(Run.cancel(run))
      :ok
    else
      {:error, :not_found} -> :ok
      false -> {:error, :run_session_mismatch}
    end
  end

  defp execute_run(%Session{session_type: :local_echo} = session, %RunRequest{} = request, opts) do
    with {:ok, %Run{} = started_run} <- LocalEcho.start_run(session, request, opts),
         {:ok, %Run{} = completed_run} <-
           LocalEcho.complete_run(session, started_run, request, opts) do
      {:ok, started_run, completed_run}
    end
  end

  defp persist_run(%Session{} = session, %Run{} = run) do
    updated_session = Session.attach_run(session, run.run_id, run.completed_at || run.started_at)

    with :ok <- Store.put_run(run) do
      Store.put_session(updated_session)
    end
  end

  defp build_session(opts, boundary) when is_list(opts) do
    opts
    |> apply_boundary_session_opts(boundary)
    |> Session.new()
  end

  defp maybe_prepare_boundary(opts) when is_list(opts) do
    adapter = Keyword.get(opts, :boundary_adapter)
    adapter_opts = Keyword.get(opts, :boundary_adapter_opts, [])
    runtime_owner = Keyword.get(opts, :boundary_runtime_owner, "jido_session")
    runtime_ref = boundary_runtime_ref(opts)

    cond do
      boundary_request = Keyword.get(opts, :boundary_request) ->
        with {:ok, descriptor} <-
               BoundaryBridge.allocate(
                 boundary_request,
                 boundary_bridge_opts(adapter, adapter_opts)
               ),
             :ok <- ensure_supported_boundary_descriptor(descriptor),
             {:ok, descriptor} <-
               BoundaryBridge.claim(
                 descriptor,
                 boundary_bridge_opts(adapter, adapter_opts,
                   runtime_owner: runtime_owner,
                   runtime_ref: runtime_ref
                 )
               ),
             :ok <- ensure_supported_boundary_descriptor(descriptor) do
          {:ok, %{descriptor: descriptor}}
        end

      boundary_reopen_request = Keyword.get(opts, :boundary_reopen_request) ->
        with {:ok, descriptor} <-
               BoundaryBridge.reopen(
                 boundary_reopen_request,
                 boundary_bridge_opts(adapter, adapter_opts)
               ),
             :ok <- ensure_supported_boundary_descriptor(descriptor),
             {:ok, descriptor} <-
               BoundaryBridge.claim(
                 descriptor,
                 boundary_bridge_opts(adapter, adapter_opts,
                   runtime_owner: runtime_owner,
                   runtime_ref: runtime_ref
                 )
               ),
             :ok <- ensure_supported_boundary_descriptor(descriptor) do
          {:ok, %{descriptor: descriptor}}
        end

      true ->
        {:ok, nil}
    end
  end

  defp ensure_supported_boundary_descriptor(%{descriptor_version: 1}), do: :ok

  defp ensure_supported_boundary_descriptor(%{descriptor_version: version}) do
    {:error,
     Error.validation_error("unsupported boundary descriptor_version", %{
       descriptor_version: version,
       supported_versions: [1]
     })}
  end

  defp apply_boundary_session_opts(opts, nil), do: opts

  defp apply_boundary_session_opts(opts, %{descriptor: descriptor} = boundary) do
    metadata =
      opts
      |> Keyword.get(:metadata, %{})
      |> normalize_map()
      |> Map.put("boundary", boundary_metadata(boundary))

    opts
    |> Keyword.put(:metadata, metadata)
    |> Keyword.put_new(
      :cwd,
      descriptor.attach.working_directory || descriptor.workspace.workspace_root
    )
  end

  defp boundary_metadata(%{descriptor: descriptor}) do
    %{
      "descriptor" => normalize_value(Map.from_struct(descriptor))
    }
  end

  defp boundary_runtime_ref(opts) do
    Keyword.get(opts, :boundary_runtime_ref) || Keyword.get(opts, :session_id)
  end

  defp boundary_bridge_opts(adapter, adapter_opts, extra_opts \\ []) do
    []
    |> maybe_put(:adapter, adapter)
    |> Keyword.put(:adapter_opts, adapter_opts)
    |> Keyword.merge(extra_opts)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(value) when is_list(value), do: Map.new(value)
  defp normalize_map(_value), do: %{}

  defp normalize_value(nil), do: nil
  defp normalize_value(value) when is_boolean(value), do: value
  defp normalize_value(value) when is_integer(value), do: value
  defp normalize_value(value) when is_float(value), do: value
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_value(%_{} = value) do
    value
    |> Map.from_struct()
    |> normalize_value()
  end

  defp normalize_value(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {to_string(key), normalize_value(nested_value)} end)
  end

  defp normalize_value(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Map.new(value, fn {key, nested_value} -> {to_string(key), normalize_value(nested_value)} end)
    else
      Enum.map(value, &normalize_value/1)
    end
  end

  defp normalize_value(value), do: value
end
