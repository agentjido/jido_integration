defmodule Jido.Integration.Docs.ConnectorReadmesTest do
  use ExUnit.Case, async: true

  @readmes [
    Path.expand("../../connectors/github/README.md", __DIR__),
    Path.expand("../../connectors/notion/README.md", __DIR__),
    Path.expand("../../connectors/codex_cli/README.md", __DIR__),
    Path.expand("../../connectors/market_data/README.md", __DIR__)
  ]

  test "connector packages publish the baseline Phase 9 review sections" do
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

      refute Regex.match?(~r/\bbridge(?:d|s)?\b/i, readme),
             "#{path} must not preserve removed bridge wording"
    end
  end

  test "direct connector READMEs encode authored auth truth, install modes, and lease-built SDK clients" do
    github_readme =
      readme(Path.expand("../../connectors/github/README.md", __DIR__))
      |> normalize_whitespace()

    assert github_readme =~
             "the manifest is the authored source of truth for `supported_profiles`, install modes, and reauth posture"

    assert github_readme =~
             "supports manual token entry or external-secret completion with no callback"

    assert github_readme =~
             "supports browser OAuth plus hosted or manual callback completion with state correlation"

    assert github_readme =~
             "builds `GitHubEx.Client` instances from those leases only"

    assert github_readme =~
             "Those generated outputs are derivative only."

    notion_readme =
      readme(Path.expand("../../connectors/notion/README.md", __DIR__))
      |> normalize_whitespace()

    assert notion_readme =~
             "the manifest is the authored source of truth for `supported_profiles`, install modes, and reauth posture"

    assert notion_readme =~ "browser OAuth with hosted callback completion"
    assert notion_readme =~ "browser OAuth with manual callback completion"
    assert notion_readme =~ "external-secret completion"
    assert notion_readme =~ "builds `NotionSDK.Client` instances from those leases only"

    assert notion_readme =~
             "Those generated actions, sensors, and plugin subscriptions are derivative only."
  end

  defp readme(path), do: File.read!(path)

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
