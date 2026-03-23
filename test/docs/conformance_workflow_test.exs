defmodule Jido.Integration.Docs.ConformanceWorkflowTest do
  use ExUnit.Case, async: true

  @guide_path Path.expand("../../docs/conformance_workflow.md", __DIR__)

  test "documents conformance as a connector acceptance contract" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert guide =~ "## Connector Acceptance Contract"

    assert guide =~
             "A connector package is not review-complete until its package-local verification, root conformance, and root acceptance gates all pass."

    assert guide =~
             "The companion module is the connector-owned publication point for deterministic fixtures, runtime-driver evidence, and ingress definitions."

    assert guide =~
             "Package-local fixtures stay package-local even though `mix jido.conformance <ConnectorModule>` runs from the workspace root."

    assert guide =~ "mix ci"
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
