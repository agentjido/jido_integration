defmodule Jido.Integration.Docs.ConnectorScaffoldingTest do
  use ExUnit.Case, async: true

  @guide_path Path.expand("../../docs/connector_scaffolding.md", __DIR__)

  test "documents the Phase 0 scaffold as direct-only" do
    guide = File.read!(@guide_path)

    assert guide =~ "The workspace scaffold currently supports direct connectors only."
    assert guide =~ "`asm` or `jido_session`"

    refute guide =~ "mix jido.integration.new analyst_cli --runtime-class session"
    refute guide =~ "mix jido.integration.new market_feed --runtime-class stream"
  end
end
