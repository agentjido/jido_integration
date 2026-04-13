defmodule Jido.Integration.V2.Connectors.Notion.ConformanceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Conformance
  alias Jido.Integration.V2.Connectors.Notion
  alias Jido.Integration.V2.Connectors.Notion.Fixtures
  alias Jido.Integration.V2.Connectors.Notion.OperationCatalog

  test "publishes deterministic conformance fixtures for the full A0 slice" do
    assert Enum.map(Notion.Conformance.fixtures(), & &1.capability_id) ==
             Fixtures.published_capability_ids()
  end

  test "uses late-bound fixture inputs that exercise schema resolution for the published Notion A0 slice" do
    fixtures = Map.new(Notion.Conformance.fixtures(), &{&1.capability_id, &1})

    assert get_in(fixtures["notion.pages.create"], [:input, :parent, "data_source_id"]) ==
             Fixtures.data_source_id()

    assert get_in(fixtures["notion.pages.update"], [:input, :properties, "Title"]) != nil

    assert get_in(fixtures["notion.data_sources.query"], [:input, :filter, :property]) == "Status"
    assert get_in(fixtures["notion.data_sources.query"], [:input, :sorts]) != nil
  end

  test "passes connector foundation conformance with the package-local fixture seam" do
    assert {:ok, report} =
             Conformance.run(
               Notion,
               profile: :connector_foundation,
               generated_at: ~U[2026-03-12 00:00:00Z]
             )

    assert report.status == :passed

    deterministic_suite =
      Enum.find(report.suite_results, &(&1.id == :deterministic_fixtures))

    assert deterministic_suite.status == :passed

    assert Enum.map(Notion.Conformance.fixtures(), fn fixture ->
             entry = OperationCatalog.fetch!(fixture.capability_id)

             {fixture.capability_id,
              [
                "attempt.started",
                "connector.notion.#{entry.event_suffix}.completed",
                "attempt.completed"
              ]}
           end) ==
             Enum.map(Notion.Conformance.fixtures(), fn fixture ->
               expected =
                 fixture.expect
                 |> Map.fetch!(:event_types)

               {fixture.capability_id, expected}
             end)
  end
end
