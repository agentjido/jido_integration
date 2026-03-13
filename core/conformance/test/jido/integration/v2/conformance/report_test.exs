defmodule Jido.Integration.V2.Conformance.ReportTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Conformance.CheckResult
  alias Jido.Integration.V2.Conformance.Renderer
  alias Jido.Integration.V2.Conformance.Report
  alias Jido.Integration.V2.Conformance.SuiteResult

  test "renders stable JSON and human output for a report" do
    report = sample_report()

    json = Renderer.render(report, :json)
    human = Renderer.render(report, :human)
    decoded = Jason.decode!(json)

    assert decoded["connector_id"] == "github"
    assert decoded["profile"] == "connector_foundation"
    assert decoded["status"] == "passed"

    assert Enum.map(decoded["suite_results"], & &1["id"]) == [
             "manifest_contract",
             "ingress_definition_discipline"
           ]

    assert human =~ "Connector: github"
    assert human =~ "[PASS] manifest_contract"
    assert human =~ "[SKIP] ingress_definition_discipline"
  end

  defp sample_report do
    %Report{
      connector_module: Jido.Integration.V2.Connectors.GitHub,
      connector_id: "github",
      profile: :connector_foundation,
      runner_version: "0.1.0",
      generated_at: ~U[2026-03-12 00:00:00Z],
      status: :passed,
      suite_results: [
        SuiteResult.from_checks(
          :manifest_contract,
          [
            CheckResult.pass("manifest.connector.present")
          ],
          "Manifest and connector identity stay deterministic"
        ),
        SuiteResult.skip(
          :ingress_definition_discipline,
          "connector publishes no ingress-trigger capabilities"
        )
      ]
    }
  end
end
