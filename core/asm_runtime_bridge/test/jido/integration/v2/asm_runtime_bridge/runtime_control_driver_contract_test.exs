defmodule Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriverContractTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.AsmRuntimeBridge.SessionStore
  alias Jido.Integration.V2.AsmRuntimeBridge.TestSupport.StreamScriptedDriver

  setup do
    ensure_asm_runtime_bridge_started!()
    SessionStore.reset!()
    :ok
  end

  use Jido.RuntimeControl.RuntimeDriverContract,
    driver: Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriver,
    start_session_opts: [provider: :claude],
    check_stream_run: true,
    check_run: true,
    run_request: %{prompt: "contract test", metadata: %{}},
    run_opts: [driver: StreamScriptedDriver]

  defp ensure_asm_runtime_bridge_started! do
    case Jido.Integration.V2.AsmRuntimeBridge.Application.start(:normal, []) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> flunk("failed to start asm_runtime_bridge: #{inspect(reason)}")
    end
  end
end
