defmodule Jido.Integration.V2.ExecutionRouter do
  @moduledoc """
  Stable runtime-family routing seam for the control plane.
  """

  alias Jido.Integration.V2.{
    Capability,
    ControlPlane.RuntimeConfig,
    DirectRuntime,
    RuntimeResult,
    UnsupportedNonDirectRuntime
  }

  @default_non_direct_runtime_adapter Jido.Integration.V2.RuntimeRouter

  @spec execute(Capability.t(), map(), map()) ::
          {:ok, RuntimeResult.t()} | {:error, term(), RuntimeResult.t()}
  def execute(%Capability{runtime_class: :direct} = capability, input, context) do
    DirectRuntime.execute(capability, input, context)
  end

  def execute(%Capability{runtime_class: runtime_class} = capability, input, context)
      when runtime_class in [:session, :stream] do
    non_direct_runtime_adapter()
    |> if_non_direct_runtime_available(
      fn adapter -> adapter.execute(capability, input, context) end,
      fn -> UnsupportedNonDirectRuntime.execute(capability, input, context) end
    )
  end

  @doc false
  @spec cleanup_runtime_session(String.t(), atom()) :: :ok | {:error, term()}
  def cleanup_runtime_session(session_id, reason)
      when is_binary(session_id) and is_atom(reason) do
    non_direct_runtime_adapter()
    |> if_non_direct_runtime_available(
      fn adapter ->
        if function_exported?(adapter, :cleanup_runtime_session, 2),
          do: adapter.cleanup_runtime_session(session_id, reason),
          else: {:error, :runtime_session_cleanup_unsupported}
      end,
      fn -> {:error, :non_direct_runtime_unavailable} end
    )
  end

  @spec reset!() :: :ok
  def reset! do
    non_direct_runtime_adapter()
    |> if_non_direct_runtime_available(fn adapter -> adapter.reset!() end, fn -> :ok end)
  end

  defp non_direct_runtime_adapter do
    RuntimeConfig.current().non_direct_runtime_adapter || @default_non_direct_runtime_adapter
  end

  defp if_non_direct_runtime_available(adapter, present_fun, absent_fun) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :execute, 3) do
      present_fun.(adapter)
    else
      absent_fun.()
    end
  end
end
