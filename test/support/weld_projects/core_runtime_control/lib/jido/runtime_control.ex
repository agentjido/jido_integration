defmodule Jido.RuntimeControl do
  @moduledoc """
  Shared Session Control facade for runtime drivers.

  `Jido.RuntimeControl` owns the public IR and driver-facing facade used by the
  integration runtime path. Concrete runtime packages register
  `Jido.RuntimeControl.RuntimeDriver` implementations under
  `:jido_runtime_control, :runtime_drivers`.
  """

  alias Jido.RuntimeControl.{
    Error,
    RunRequest,
    Runtime,
    RuntimeDescriptor,
    RuntimeRegistry,
    SessionHandle
  }

  @doc """
  Returns available Session Control runtime drivers.
  """
  @spec runtime_drivers() :: [RuntimeDescriptor.t()]
  def runtime_drivers do
    RuntimeRegistry.runtime_drivers()
    |> Enum.sort_by(fn {runtime_id, _module} -> runtime_id end)
    |> Enum.map(fn {_runtime_id, module} ->
      {:ok, descriptor} = Runtime.runtime_descriptor(module, [])
      descriptor
    end)
  end

  @doc """
  Returns the configured or discovered default runtime driver.
  """
  @spec default_runtime_driver() :: atom() | nil
  def default_runtime_driver, do: RuntimeRegistry.default_runtime_driver()

  @doc """
  Returns a runtime descriptor for the selected Session Control runtime driver.
  """
  @spec runtime_descriptor(atom(), keyword()) :: {:ok, RuntimeDescriptor.t()} | {:error, term()}
  def runtime_descriptor(runtime_id, opts \\ []) when is_atom(runtime_id) and is_list(opts) do
    with {:ok, module} <- RuntimeRegistry.lookup(runtime_id) do
      Runtime.runtime_descriptor(module, opts)
    end
  end

  @doc """
  Starts a Session Control runtime session using the default runtime driver.
  """
  @spec start_session(keyword()) :: {:ok, SessionHandle.t()} | {:error, term()}
  def start_session(opts \\ []) when is_list(opts) do
    case RuntimeRegistry.default_runtime_driver() do
      nil ->
        {:error,
         Error.validation_error("No default runtime driver is configured", %{
           field: :default_runtime_driver
         })}

      runtime_id ->
        start_session(runtime_id, opts)
    end
  end

  @doc """
  Starts a Session Control runtime session using a specific runtime driver.
  """
  @spec start_session(atom(), keyword()) :: {:ok, SessionHandle.t()} | {:error, term()}
  def start_session(runtime_id, opts) when is_atom(runtime_id) and is_list(opts) do
    with {:ok, module} <- RuntimeRegistry.lookup(runtime_id) do
      Runtime.start_session(module, opts)
    end
  end

  @doc """
  Stops a Session Control runtime session.
  """
  @spec stop_session(SessionHandle.t()) :: :ok | {:error, term()}
  def stop_session(%SessionHandle{} = session) do
    with {:ok, module} <- RuntimeRegistry.lookup(session.runtime_id) do
      Runtime.stop_session(module, session)
    end
  end

  @doc """
  Runs a streaming Session Control execution against an existing session.
  """
  @spec stream_run(SessionHandle.t(), RunRequest.t(), keyword()) ::
          {:ok, Jido.RuntimeControl.RunHandle.t(), Enumerable.t(Jido.RuntimeControl.ExecutionEvent.t())}
          | {:error, term()}
  def stream_run(%SessionHandle{} = session, %RunRequest{} = request, opts \\ []) when is_list(opts) do
    with {:ok, module} <- RuntimeRegistry.lookup(session.runtime_id) do
      Runtime.stream_run(module, session, request, opts)
    end
  end

  @doc """
  Runs a Session Control execution to completion against an existing session.
  """
  @spec run_result(SessionHandle.t(), RunRequest.t(), keyword()) ::
          {:ok, Jido.RuntimeControl.ExecutionResult.t()} | {:error, term()}
  def run_result(%SessionHandle{} = session, %RunRequest{} = request, opts \\ []) when is_list(opts) do
    with {:ok, module} <- RuntimeRegistry.lookup(session.runtime_id) do
      Runtime.run_result(module, session, request, opts)
    end
  end

  @doc """
  Cancels an active Session Control run.
  """
  @spec cancel_run(SessionHandle.t(), Jido.RuntimeControl.RunHandle.t() | String.t()) :: :ok | {:error, term()}
  def cancel_run(%SessionHandle{} = session, run_or_id) do
    with {:ok, module} <- RuntimeRegistry.lookup(session.runtime_id) do
      Runtime.cancel_run(module, session, run_or_id)
    end
  end

  @doc """
  Returns Session Control runtime session status.
  """
  @spec session_status(SessionHandle.t()) ::
          {:ok, Jido.RuntimeControl.ExecutionStatus.t()} | {:error, term()}
  def session_status(%SessionHandle{} = session) do
    with {:ok, module} <- RuntimeRegistry.lookup(session.runtime_id) do
      Runtime.session_status(module, session)
    end
  end

  @doc """
  Resolves a Session Control approval.
  """
  @spec approve(SessionHandle.t(), String.t(), :allow | :deny, keyword()) :: :ok | {:error, term()}
  def approve(%SessionHandle{} = session, approval_id, decision, opts \\ []) when is_list(opts) do
    with {:ok, module} <- RuntimeRegistry.lookup(session.runtime_id) do
      Runtime.approve(module, session, approval_id, decision, opts)
    end
  end

  @doc """
  Returns normalized cost data for a Session Control runtime session.
  """
  @spec cost(SessionHandle.t()) :: {:ok, map()} | {:error, term()}
  def cost(%SessionHandle{} = session) do
    with {:ok, module} <- RuntimeRegistry.lookup(session.runtime_id) do
      Runtime.cost(module, session)
    end
  end
end
