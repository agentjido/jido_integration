defmodule Jido.Integration.V2.RuntimeAsmBridge.HarnessDriverContractTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.RuntimeAsmBridge.SessionStore
  alias Jido.Integration.V2.RuntimeAsmBridge.TestSupport.StreamScriptedDriver

  setup do
    ensure_runtime_asm_bridge_started!()
    SessionStore.reset!()
    :ok
  end

  use Jido.Harness.RuntimeDriverContract,
    driver: Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver,
    start_session_opts: [provider: :claude],
    check_stream_run: true,
    check_run: true,
    run_request: %{prompt: "contract test", metadata: %{}},
    run_opts: [driver: StreamScriptedDriver]

  defp ensure_runtime_asm_bridge_started! do
    case Jido.Integration.V2.RuntimeAsmBridge.Application.start(:normal, []) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> flunk("failed to start runtime_asm_bridge: #{inspect(reason)}")
    end
  end
end
