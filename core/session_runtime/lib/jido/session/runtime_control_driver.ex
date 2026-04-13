defmodule Jido.Session.RuntimeControlDriver do
  @moduledoc """
  Runtime Control driver for the internal `jido_session` kernel.
  """

  @behaviour Jido.RuntimeControl.RuntimeDriver

  alias Jido.RuntimeControl.{
    ExecutionResult,
    ExecutionStatus,
    RunHandle,
    RunRequest,
    RuntimeDescriptor,
    SessionHandle
  }

  alias Jido.Session

  @impl true
  @spec runtime_id() :: atom()
  def runtime_id, do: Session.runtime_id()

  @impl true
  @spec runtime_descriptor(keyword()) :: RuntimeDescriptor.t()
  def runtime_descriptor(opts \\ []), do: Session.runtime_descriptor(opts)

  @impl true
  @spec start_session(keyword()) :: {:ok, SessionHandle.t()} | {:error, term()}
  def start_session(opts), do: Session.start_session(opts)

  @impl true
  @spec stop_session(SessionHandle.t()) :: :ok | {:error, term()}
  def stop_session(session), do: Session.stop_session(session)

  @impl true
  @spec stream_run(SessionHandle.t(), RunRequest.t(), keyword()) ::
          {:ok, RunHandle.t(), Enumerable.t(Jido.RuntimeControl.ExecutionEvent.t())}
          | {:error, term()}
  def stream_run(session, request, opts), do: Session.stream_run(session, request, opts)

  @impl true
  @spec cancel_run(SessionHandle.t(), RunHandle.t() | String.t()) :: :ok | {:error, term()}
  def cancel_run(session, run_or_id), do: Session.cancel_run(session, run_or_id)

  @impl true
  @spec session_status(SessionHandle.t()) :: {:ok, ExecutionStatus.t()} | {:error, term()}
  def session_status(session), do: Session.session_status(session)

  @impl true
  @spec run(SessionHandle.t(), RunRequest.t(), keyword()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def run(session, request, opts), do: Session.run(session, request, opts)
end
