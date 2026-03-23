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

  test "connector packages keep package-local verification and live-proof ownership explicit" do
    Enum.each(@readmes, fn path ->
      readme = File.read!(path)

      assert readme =~ "mix compile --warnings-as-errors",
             "#{path} must document package-local compile verification"

      assert readme =~ "mix test", "#{path} must document package-local test verification"
      assert readme =~ "mix docs", "#{path} must document package-local docs verification"
      assert readme =~ "mix jido.conformance", "#{path} must document root conformance"
      assert readme =~ "mix ci", "#{path} must document root acceptance"
    end)

    assert readme(Path.expand("../../connectors/github/README.md", __DIR__)) =~
             "Package-local live proofs exist"

    assert readme(Path.expand("../../connectors/notion/README.md", __DIR__)) =~
             "Package-local live proofs exist"

    assert readme(Path.expand("../../connectors/codex_cli/README.md", __DIR__)) =~
             "No package-local live proof exists yet"

    assert readme(Path.expand("../../connectors/market_data/README.md", __DIR__)) =~
             "No package-local live proof exists yet"
  end

  defp readme(path), do: File.read!(path)
end
