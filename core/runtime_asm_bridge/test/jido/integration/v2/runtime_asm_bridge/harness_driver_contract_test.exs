defmodule Jido.Integration.V2.RuntimeAsmBridge.HarnessDriverContractTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.RuntimeAsmBridge.SessionStore
  alias Jido.Integration.V2.RuntimeAsmBridge.TestSupport.StreamScriptedDriver

  setup do
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
end
