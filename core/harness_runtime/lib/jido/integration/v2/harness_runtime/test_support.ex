defmodule Jido.Integration.V2.HarnessRuntime.TestSupport do
  @moduledoc false

  @spec ensure_started!() :: :ok
  def ensure_started! do
    case Jido.Integration.V2.HarnessRuntime.Application.start(:normal, []) do
      {:ok, pid} ->
        Process.unlink(pid)
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "failed to start harness runtime test support: #{inspect(reason)}"
    end
  end
end
