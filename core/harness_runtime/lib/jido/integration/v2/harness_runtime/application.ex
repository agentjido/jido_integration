defmodule Jido.Integration.V2.HarnessRuntime.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ensure_dependency_started!(
      Jido.Integration.V2.RuntimeAsmBridge.Application,
      "runtime_asm_bridge"
    )

    ensure_dependency_started!(Jido.Session.Application, "jido_session")

    children = [
      {Jido.Integration.V2.HarnessRuntime.SessionStore, []}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Jido.Integration.V2.HarnessRuntime.Supervisor
    )
  end

  defp ensure_dependency_started!(application_module, label) do
    case application_module.start(:normal, []) do
      {:ok, pid} ->
        Process.unlink(pid)
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "harness runtime dependency #{label} did not start: #{inspect(reason)}"
    end
  end
end
