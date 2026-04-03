defmodule Jido.Integration.V2.Connectors.Linear.ConformanceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Conformance
  alias Jido.Integration.V2.Connectors.Linear
  alias Jido.Integration.V2.Connectors.Linear.Fixtures

  test "publishes deterministic conformance fixtures for the full A0 slice" do
    assert Enum.map(Linear.Conformance.fixtures(), & &1.capability_id) ==
             Fixtures.published_capability_ids()
  end

  test "passes connector foundation conformance with the package-local linear_sdk fixture seam" do
    assert {:ok, report} =
             Conformance.run(
               Linear,
               profile: :connector_foundation,
               generated_at: ~U[2026-04-02 00:00:00Z]
             )

    assert report.status == :passed, inspect(report, pretty: true, limit: :infinity)

    deterministic_suite =
      Enum.find(report.suite_results, &(&1.id == :deterministic_fixtures))

    assert deterministic_suite.status == :passed
  end
end
