defmodule Jido.Integration.V2.Connectors.Notion.Conformance do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.Notion
  alias Jido.Integration.V2.Connectors.Notion.Fixtures
  alias Jido.Integration.V2.Connectors.Notion.OperationCatalog
  alias Jido.Integration.V2.TriggerSpec

  @spec fixtures() :: [map()]
  def fixtures do
    Enum.map(Fixtures.published_capability_ids(), &fixture_for/1)
  end

  @spec ingress_definitions() :: [map()]
  def ingress_definitions do
    connector_id = Notion.manifest().connector

    Enum.map(Notion.manifest().triggers, fn trigger ->
      %{
        source: :poll,
        connector_id: connector_id,
        trigger_id: trigger.trigger_id,
        capability_id: trigger.trigger_id,
        signal_type: TriggerSpec.sensor_signal_type(trigger),
        signal_source: TriggerSpec.sensor_signal_source(trigger)
      }
    end)
  end

  defp fixture_for(capability_id) do
    entry = OperationCatalog.fetch!(capability_id)
    context = Fixtures.conformance_context()

    %{
      capability_id: capability_id,
      input: Fixtures.input_for(capability_id),
      credential_ref: Fixtures.credential_ref_attrs(),
      credential_lease: Fixtures.credential_lease_attrs(),
      context: context,
      expect: %{
        output: %{
          capability_id: capability_id,
          auth_binding: Fixtures.auth_binding(),
          data: Fixtures.output_data(capability_id)
        },
        event_types: [
          "attempt.started",
          "connector.notion.#{entry.event_suffix}.completed",
          "attempt.completed"
        ],
        artifact_types: [:tool_output],
        artifact_keys: [
          "notion/#{context.run_id}/#{context.attempt_id}/#{entry.artifact_slug}.term"
        ]
      }
    }
  end
end
