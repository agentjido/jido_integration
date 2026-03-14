defmodule Jido.Integration.V2.Connectors.NotionConformanceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Conformance

  test "passes the connector foundation profile" do
    assert {:ok, report} =
             Conformance.run(
               Jido.Integration.V2.Connectors.Notion,
               profile: :connector_foundation,
               generated_at: ~U[2026-03-12 00:00:00Z]
             )

    assert report.status == :passed
  end
end
