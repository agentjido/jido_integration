defmodule Jido.Integration.V2.HarnessRuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.HarnessRuntime
  alias Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver

  test "publishes asm and jido_session as the only target Harness driver ids" do
    assert HarnessRuntime.target_driver_ids() == ["asm", "jido_session"]
  end

  test "keeps integration-owned bridge drivers available only as compatibility shims" do
    assert HarnessRuntime.compatibility_driver_ids() == [
             "integration_session_bridge",
             "integration_stream_bridge"
           ]

    assert {:ok, Jido.Integration.V2.SessionKernel.HarnessDriver} =
             HarnessRuntime.driver_module("integration_session_bridge")

    assert {:ok, Jido.Integration.V2.StreamRuntime.HarnessDriver} =
             HarnessRuntime.driver_module("integration_stream_bridge")
  end

  test "resolves asm to the target Harness runtime driver" do
    assert {:ok, HarnessDriver} = HarnessRuntime.driver_module("asm")
    assert {:ok, Jido.Session.HarnessDriver} = HarnessRuntime.driver_module("jido_session")
  end
end
