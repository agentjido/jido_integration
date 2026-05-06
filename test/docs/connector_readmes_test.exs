defmodule Jido.Integration.Docs.ConnectorReadmesTest do
  use ExUnit.Case, async: true

  @readmes [
    Path.expand("../../connectors/github/README.md", __DIR__),
    Path.expand("../../connectors/linear/README.md", __DIR__),
    Path.expand("../../connectors/notion/README.md", __DIR__),
    Path.expand("../../connectors/codex_cli/README.md", __DIR__),
    Path.expand("../../connectors/market_data/README.md", __DIR__)
  ]

  test "connector packages publish the baseline Phase 9 review sections" do
    Enum.each(@readmes, fn path ->
      readme = File.read!(path)

      assert String.contains?(readme, "## Runtime And Auth Posture"),
             "#{path} is missing runtime/auth posture"

      assert String.contains?(readme, "## Package Verification"),
             "#{path} is missing package verification"

      assert String.contains?(readme, "## Live Proof Status"),
             "#{path} is missing live-proof status"

      assert String.contains?(readme, "## Package Boundary"),
             "#{path} is missing package boundary"
    end)
  end

  test "connector packages keep package-local verification and live-proof ownership explicit" do
    Enum.each(@readmes, fn path ->
      readme = File.read!(path)

      assert String.contains?(readme, "mix compile --warnings-as-errors"),
             "#{path} must document package-local compile verification"

      assert String.contains?(readme, "mix test"),
             "#{path} must document package-local test verification"

      assert String.contains?(readme, "mix docs"),
             "#{path} must document package-local docs verification"

      assert String.contains?(readme, "mix jido.conformance"),
             "#{path} must document root conformance"

      assert String.contains?(readme, "mix ci"), "#{path} must document root acceptance"
    end)

    assert String.contains?(
             readme(Path.expand("../../connectors/github/README.md", __DIR__)),
             "Package-local live proofs exist"
           )

    assert String.contains?(
             readme(Path.expand("../../connectors/notion/README.md", __DIR__)),
             "Package-local live proofs exist"
           )

    assert String.contains?(
             readme(Path.expand("../../connectors/linear/README.md", __DIR__)),
             "Package-local live proof entry points now live"
           )

    assert String.contains?(
             readme(Path.expand("../../connectors/codex_cli/README.md", __DIR__)),
             "No package-local live proof exists yet"
           )

    assert String.contains?(
             readme(Path.expand("../../connectors/market_data/README.md", __DIR__)),
             "No package-local live proof exists yet"
           )
  end

  test "market_data README keeps generated sensor references on the public projection contract" do
    market_data_readme =
      readme(Path.expand("../../connectors/market_data/README.md", __DIR__))

    refute String.contains?(
             market_data_readme,
             "Jido.Integration.V2.Connectors.MarketData.Generated.Sensors.MarketAlertsDetected"
           )

    assert String.contains?(
             market_data_readme,
             "`Jido.Integration.V2.ConsumerProjection.sensor_module/2`"
           )
  end

  test "direct connector READMEs keep the provider-SDK boundary explicit" do
    for {path, sdk_dep} <- [
          {Path.expand("../../connectors/github/README.md", __DIR__), "`github_ex`"},
          {Path.expand("../../connectors/linear/README.md", __DIR__), "`linear_sdk`"},
          {Path.expand("../../connectors/notion/README.md", __DIR__), "`notion_sdk`"}
        ] do
      readme = path |> readme() |> normalize_whitespace()

      assert String.contains?(readme, "stays on the direct provider-SDK path"),
             "#{path} must describe the direct provider-SDK lane explicitly"

      assert String.contains?(
               readme,
               "does not inherit session or stream runtime-kernel coupling"
             ),
             "#{path} must reject non-direct runtime coupling explicitly"

      assert String.contains?(readme, sdk_dep), "#{path} must name its provider SDK boundary"

      refute String.contains?(readme, "Jido.RuntimeControl"),
             "#{path} must not describe a runtime-control-routed path"

      refute bridge_word?(readme),
             "#{path} must not preserve removed bridge wording"
    end
  end

  test "direct connector READMEs encode authored auth truth, install modes, and lease-built SDK clients" do
    github_readme =
      readme(Path.expand("../../connectors/github/README.md", __DIR__))
      |> normalize_whitespace()

    assert String.contains?(
             github_readme,
             "the manifest is the authored source of truth for `supported_profiles`, install modes, and reauth posture"
           )

    assert String.contains?(
             github_readme,
             "supports manual token entry or external-secret completion with no callback"
           )

    assert String.contains?(
             github_readme,
             "supports browser OAuth plus hosted or manual callback completion with state correlation"
           )

    assert String.contains?(
             github_readme,
             "builds `GitHubEx.Client` instances from those leases only"
           )

    assert String.contains?(
             github_readme,
             "Those generated outputs are derivative only."
           )

    linear_readme =
      readme(Path.expand("../../connectors/linear/README.md", __DIR__))
      |> normalize_whitespace()

    assert String.contains?(
             linear_readme,
             "the manifest is the authored source of truth for `supported_profiles`, install modes, and reauth posture"
           )

    assert String.contains?(
             linear_readme,
             "supports manual API key entry or external-secret completion with no callback"
           )

    assert String.contains?(
             linear_readme,
             "supports browser OAuth plus hosted or manual callback completion with state correlation"
           )

    assert String.contains?(
             linear_readme,
             "builds `LinearSDK.Client` instances from those leases only"
           )

    assert String.contains?(
             linear_readme,
             "`install_binding` remains connector-local and only feeds install, reauth, manual-auth, or rotation completion flows"
           )

    assert String.contains?(
             linear_readme,
             "`Jido.Integration.V2 -> DirectRuntime -> connector -> linear_sdk -> prismatic`"
           )

    refute String.contains?(linear_readme, "linear_sdk -> pristine")

    assert String.contains?(
             linear_readme,
             "Those generated actions and plugin exports are derivative only."
           )

    notion_readme =
      readme(Path.expand("../../connectors/notion/README.md", __DIR__))
      |> normalize_whitespace()

    assert String.contains?(
             notion_readme,
             "the manifest is the authored source of truth for `supported_profiles`, install modes, and reauth posture"
           )

    assert String.contains?(notion_readme, "browser OAuth with hosted callback completion")
    assert String.contains?(notion_readme, "browser OAuth with manual callback completion")
    assert String.contains?(notion_readme, "external-secret completion")

    assert String.contains?(
             notion_readme,
             "builds `NotionSDK.Client` instances from those leases only"
           )

    assert String.contains?(
             notion_readme,
             "Those generated actions, sensors, and plugin subscriptions are derivative only."
           )
  end

  defp readme(path), do: File.read!(path)

  defp normalize_whitespace(text), do: text |> String.split() |> Enum.join(" ")

  defp bridge_word?(text) do
    text
    |> String.downcase()
    |> String.split()
    |> Enum.any?(fn word ->
      word
      |> String.trim(".,;:!()[]{}\"'")
      |> then(&(&1 in ["bridge", "bridged", "bridges"]))
    end)
  end
end
