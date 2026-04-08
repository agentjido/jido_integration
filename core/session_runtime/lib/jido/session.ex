defmodule Jido.Session do
  @moduledoc """
  Internal Jido-native session runtime with a small deterministic first session type.

  `Jido.Session` owns the internal session kernel for app-controlled execution and
  projects its state through the Harness Session Control IR via
  `Jido.Session.HarnessDriver`.
  """

  alias Jido.Harness.{
    ExecutionResult,
    ExecutionStatus,
    RunHandle,
    RunRequest,
    SessionHandle
  }

  alias Jido.Session.Application, as: SessionApplication
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
    ensure_started!()

    with session <- Session.new(opts),
         :ok <- Store.put_session(session) do
      {:ok, HarnessProjection.session_handle(session)}
    end
  end

  @doc "Stops an internal session."
  @spec stop_session(SessionHandle.t()) :: :ok
  def stop_session(%SessionHandle{session_id: session_id}) do
    ensure_started!()

    case Store.delete_session(session_id) do
      {:ok, _session} -> :ok
      {:error, :not_found} -> :ok
    end
  end

  @doc "Fetches the richer internal session record."
  @spec fetch_session(String.t()) :: {:ok, session_record()} | {:error, :not_found}
  def fetch_session(session_id) when is_binary(session_id) do
    ensure_started!()
    Store.fetch_session(session_id)
  end

  @doc "Fetches the richer internal run record."
  @spec fetch_run(String.t()) :: {:ok, run_record()} | {:error, :not_found}
  def fetch_run(run_id) when is_binary(run_id) do
    ensure_started!()
    Store.fetch_run(run_id)
  end

  @doc "Projects session status through the Harness Session Control IR."
  @spec session_status(SessionHandle.t()) :: {:ok, ExecutionStatus.t()} | {:error, term()}
  def session_status(%SessionHandle{session_id: session_id}) do
    ensure_started!()

    with {:ok, %Session{} = session} <- Store.fetch_session(session_id) do
      {:ok, HarnessProjection.session_status(session)}
    end
  end

  @doc "Runs a deterministic streaming execution and returns projected IR events."
  @spec stream_run(SessionHandle.t(), RunRequest.t(), keyword()) ::
          {:ok, RunHandle.t(), Enumerable.t(Jido.Harness.ExecutionEvent.t())} | {:error, term()}
  def stream_run(%SessionHandle{session_id: session_id}, %RunRequest{} = request, opts \\ []) do
    ensure_started!()

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
    ensure_started!()

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
    ensure_started!()

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

  defp ensure_started! do
    case Process.whereis(Store) do
      nil ->
        ensure_store_started!()

      _pid ->
        :ok
    end
  end

  defp ensure_store_started! do
    case Process.whereis(Jido.Session.Supervisor) do
      nil -> start_session_runtime_application!()
      _pid -> restart_session_runtime_store!()
    end

    wait_for_process!(Store, "session runtime store")
  end

  defp start_session_runtime_application! do
    case SessionApplication.start(:normal, []) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        raise("session runtime application did not start: #{inspect(reason)}")
    end
  end

  defp restart_session_runtime_store! do
    case Supervisor.restart_child(Jido.Session.Supervisor, Store) do
      {:ok, _child} -> :ok
      {:ok, _child, _info} -> :ok
      {:error, :already_present} -> :ok
      {:error, :running} -> :ok
      {:error, reason} -> raise("session runtime store did not restart: #{inspect(reason)}")
    end
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
end
