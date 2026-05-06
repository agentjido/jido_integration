defmodule Jido.Integration.Docs.ConnectorScaffoldingTest do
  use ExUnit.Case, async: true

  @guide_path Path.expand("../../docs/connector_scaffolding.md", __DIR__)

  test "documents explicit runtime-driver selection for non-direct scaffolds" do
    guide = File.read!(@guide_path)

    assert String.contains?(guide, "--runtime-driver")
    assert String.contains?(guide, "`asm` or `jido_session`")

    assert String.contains?(
             guide,
             "mix jido.integration.new analyst_cli --runtime-class session --runtime-driver asm"
           )

    assert String.contains?(
             guide,
             "mix jido.integration.new market_feed --runtime-class stream --runtime-driver asm"
           )

    assert String.contains?(
             guide,
             "There is no implicit `asm` fallback for `:session` or `:stream` routing."
           )

    refute String.contains?(guide, removed_session_bridge_id())
    refute String.contains?(guide, removed_stream_bridge_id())

    refute String.contains?(
             guide,
             "The workspace scaffold currently supports direct connectors only."
           )
  end

  test "documents the authored-vs-generated boundary and package-local proof ownership" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert String.contains?(guide, "## Generated Versus Authored Checklist")
    assert String.contains?(guide, "## Proof Code Homes")

    assert String.contains?(
             guide,
             "The scaffold output is the starting contract, not the finished connector package."
           )

    assert String.contains?(
             guide,
             "Keep deterministic fixtures, companion modules, examples, scripts, and live acceptance inside the connector package."
           )

    assert String.contains?(
             guide,
             "Do not move connector proof code into the workspace root."
           )
  end

  test "documents connector-local install_binding and lease-built client_factory seams for provider SDK connectors" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert String.contains?(
             guide,
             "The scaffold intentionally does not invent provider-specific auth helpers or SDK clients."
           )

    assert String.contains?(
             guide,
             "`install_binding.ex` for install, reauth, manual-auth, or rotation-facing secret normalization"
           )

    assert String.contains?(guide, "`client_factory.ex` for runtime lease-to-client construction")

    assert String.contains?(guide, "lower-repo auth churn absorbed at the connector boundary")
  end

  test "documents the runtime basis for both supported non-direct drivers" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert String.contains?(
             guide,
             "`runtime.driver: \"asm\"` selects `Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriver` in the `jido_integration` source repo."
           )

    assert String.contains?(
             guide,
             "`runtime.driver: \"jido_session\"` selects `Jido.Session.RuntimeControlDriver` in `core/session_runtime`."
           )

    assert String.contains?(
             guide,
             "Only the `asm` branch projects further into provider-neutral `agent_session_manager`, which itself uses `cli_subprocess_core` for subprocess, event, and provider profile foundations."
           )

    refute String.contains?(guide, "/home/home/p/g/n/")
  end

  test "documents the current monorepo validation topology for non-direct scaffolds" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert String.contains?(guide, "## Current Workspace Validation Topology")
    assert String.contains?(guide, "under `core/runtime_control`")
    assert String.contains?(guide, "do not require a sibling `../jido_runtime_control` checkout")
    refute String.contains?(guide, "/home/home/p/g/n/")
  end

  defp normalize_whitespace(text), do: text |> String.split() |> Enum.join(" ")

  defp removed_session_bridge_id, do: removed_bridge_id("session")
  defp removed_stream_bridge_id, do: removed_bridge_id("stream")

  defp removed_bridge_id(kind) do
    ["integration", kind, "bridge"]
    |> Enum.join("_")
  end
end
