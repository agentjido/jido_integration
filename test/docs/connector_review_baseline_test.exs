defmodule Jido.Integration.Docs.ConnectorReviewBaselineTest do
  use ExUnit.Case, async: true

  @guide_path Path.expand("../../docs/connector_review_baseline.md", __DIR__)

  test "documents package-local verification commands for every baseline connector" do
    guide = File.read!(@guide_path)

    for connector <- ["github", "notion", "codex_cli", "market_data"] do
      assert guide =~ "cd connectors/#{connector} && mix compile --warnings-as-errors"
      assert guide =~ "cd connectors/#{connector} && mix test"
      assert guide =~ "cd connectors/#{connector} && mix docs"
    end
  end

  test "keeps root conformance and ci explicit alongside package-local review" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert guide =~
             "package-local `mix compile --warnings-as-errors`, `mix test`, and `mix docs` plus the root conformance and `mix ci` acceptance loop"

    assert guide =~ "mix jido.conformance Jido.Integration.V2.Connectors.GitHub"
    assert guide =~ "mix jido.conformance Jido.Integration.V2.Connectors.Notion"
    assert guide =~ "mix jido.conformance Jido.Integration.V2.Connectors.CodexCli"
    assert guide =~ "mix jido.conformance Jido.Integration.V2.Connectors.MarketData"
    assert guide =~ "mix ci"
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
