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

    assert guide =~ "never generate `integration_session_bridge` or `integration_stream_bridge`"
    refute guide =~ "The workspace scaffold currently supports direct connectors only."
  end
end
