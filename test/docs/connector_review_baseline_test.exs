defmodule Jido.Integration.Docs.ConnectorReviewBaselineTest do
  use ExUnit.Case, async: true

  @guide_path Path.expand("../../docs/connector_review_baseline.md", __DIR__)

  test "documents package-local verification commands for every baseline connector" do
    guide = File.read!(@guide_path)

    for connector <- ["github", "linear", "notion", "codex_cli", "market_data"] do
      assert String.contains?(
               guide,
               "cd connectors/#{connector} && mix compile --warnings-as-errors"
             )

      assert String.contains?(guide, "cd connectors/#{connector} && mix test")
      assert String.contains?(guide, "cd connectors/#{connector} && mix docs")
    end
  end

  test "keeps root conformance and ci explicit alongside package-local review" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert String.contains?(
             guide,
             "package-local `mix compile --warnings-as-errors`, `mix test`, and `mix docs` plus the root conformance and `mix ci` acceptance loop"
           )

    assert String.contains?(guide, "mix jido.conformance Jido.Integration.V2.Connectors.GitHub")
    assert String.contains?(guide, "mix jido.conformance Jido.Integration.V2.Connectors.Linear")
    assert String.contains?(guide, "mix jido.conformance Jido.Integration.V2.Connectors.Notion")
    assert String.contains?(guide, "mix jido.conformance Jido.Integration.V2.Connectors.CodexCli")

    assert String.contains?(
             guide,
             "mix jido.conformance Jido.Integration.V2.Connectors.MarketData"
           )

    assert String.contains?(guide, "mix ci")
  end

  test "documents the Phase 9 README questions for authored auth and derivative generated surfaces" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert String.contains?(
             guide,
             "runtime family, published runtime slice, and auth posture"
           )

    assert String.contains?(
             guide,
             "supported auth profiles plus the authored install and reauth modes for each published profile"
           )

    assert String.contains?(
             guide,
             "for direct provider-SDK connectors, the authored auth-control and lease-build boundary below the SDK seam"
           )

    assert String.contains?(
             guide,
             "generated actions, plugins, and sensors remain derivative outputs only"
           )
  end

  defp normalize_whitespace(text), do: text |> String.split() |> Enum.join(" ")
end
