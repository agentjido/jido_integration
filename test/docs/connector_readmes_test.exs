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

  test "market_data README keeps generated sensor references on the public projection contract" do
    market_data_readme =
      readme(Path.expand("../../connectors/market_data/README.md", __DIR__))

    refute market_data_readme =~
             "Jido.Integration.V2.Connectors.MarketData.Generated.Sensors.MarketAlertsDetected"

    assert market_data_readme =~
             "`Jido.Integration.V2.ConsumerProjection.sensor_module/2`"
  end

  test "direct connector READMEs keep the provider-SDK boundary explicit" do
    for {path, sdk_dep} <- [
          {Path.expand("../../connectors/github/README.md", __DIR__), "`github_ex`"},
          {Path.expand("../../connectors/notion/README.md", __DIR__), "`notion_sdk`"}
        ] do
      readme = path |> readme() |> normalize_whitespace()

      assert readme =~ "stays on the direct provider-SDK path",
             "#{path} must describe the direct provider-SDK lane explicitly"

      assert readme =~ "does not inherit session or stream runtime-kernel coupling",
             "#{path} must reject non-direct runtime coupling explicitly"

      assert readme =~ sdk_dep, "#{path} must name its provider SDK boundary"
      refute readme =~ "Jido.Harness", "#{path} must not describe a Harness-routed path"
      refute readme =~ "integration_session_bridge", "#{path} must not preserve bridge wording"
      refute readme =~ "integration_stream_bridge", "#{path} must not preserve bridge wording"
    end
  end

  defp readme(path), do: File.read!(path)

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
