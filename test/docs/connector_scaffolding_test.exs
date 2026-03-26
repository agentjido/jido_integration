defmodule Jido.Integration.Docs.ConnectorScaffoldingTest do
  use ExUnit.Case, async: true

  @guide_path Path.expand("../../docs/connector_scaffolding.md", __DIR__)

  test "documents explicit runtime-driver selection for non-direct scaffolds" do
    guide = File.read!(@guide_path)

    assert guide =~ "--runtime-driver"
    assert guide =~ "`asm` or `jido_session`"

    assert guide =~
             "mix jido.integration.new analyst_cli --runtime-class session --runtime-driver asm"

    assert guide =~
             "mix jido.integration.new market_feed --runtime-class stream --runtime-driver asm"

    assert guide =~ "There is no implicit `asm` fallback for `:session` or `:stream` routing."
    refute guide =~ removed_session_bridge_id()
    refute guide =~ removed_stream_bridge_id()
    refute guide =~ "The workspace scaffold currently supports direct connectors only."
  end

  test "documents the authored-vs-generated boundary and package-local proof ownership" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert guide =~ "## Generated Versus Authored Checklist"
    assert guide =~ "## Proof Code Homes"

    assert guide =~
             "The scaffold output is the starting contract, not the finished connector package."

    assert guide =~
             "Keep deterministic fixtures, companion modules, examples, scripts, and live acceptance inside the connector package."

    assert guide =~
             "Do not move connector proof code into the workspace root."
  end

  test "documents the runtime basis for both supported non-direct drivers" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert guide =~
             "`runtime.driver: \"asm\"` selects `Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver` in `/home/home/p/g/n/jido_integration`."

    assert guide =~
             "`runtime.driver: \"jido_session\"` selects `Jido.Session.HarnessDriver` in `/home/home/p/g/n/jido_integration/core/session_runtime`."

    assert guide =~
             "Only the `asm` branch projects further into provider-neutral `/home/home/p/g/n/agent_session_manager`, which itself uses `/home/home/p/g/n/cli_subprocess_core` for subprocess, event, and provider profile foundations."
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")

  defp removed_session_bridge_id, do: removed_bridge_id("session")
  defp removed_stream_bridge_id, do: removed_bridge_id("stream")

  defp removed_bridge_id(kind) do
    ["integration", kind, "bridge"]
    |> Enum.join("_")
  end
end
