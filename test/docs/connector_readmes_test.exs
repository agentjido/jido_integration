defmodule Jido.Integration.Docs.ConnectorReadmesTest do
  use ExUnit.Case, async: true

  @readmes [
    Path.expand("../../connectors/github/README.md", __DIR__),
    Path.expand("../../connectors/notion/README.md", __DIR__),
    Path.expand("../../connectors/codex_cli/README.md", __DIR__),
    Path.expand("../../connectors/market_data/README.md", __DIR__)
  ]

  test "connector packages publish the baseline Phase 6 review sections" do
    Enum.each(@readmes, fn path ->
      readme = File.read!(path)

      assert readme =~ "## Runtime And Auth Posture", "#{path} is missing runtime/auth posture"
      assert readme =~ "## Package Verification", "#{path} is missing package verification"
      assert readme =~ "## Live Proof Status", "#{path} is missing live-proof status"
      assert readme =~ "## Package Boundary", "#{path} is missing package boundary"
    end)
  end
end
