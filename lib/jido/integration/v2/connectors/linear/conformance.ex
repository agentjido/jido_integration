defmodule Jido.Integration.V2.Connectors.Linear.Conformance do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.Linear.Fixtures
  alias Jido.Integration.V2.Connectors.Linear.OperationCatalog

  @spec fixtures() :: [map()]
  def fixtures do
    Enum.map(Fixtures.published_capability_ids(), fn capability_id ->
      entry = OperationCatalog.fetch!(capability_id)

      %{
        capability_id: capability_id,
        input: Fixtures.input_for(capability_id),
        credential_ref: Fixtures.credential_ref_attrs(),
        credential_lease: Fixtures.credential_lease_attrs(),
        context: %{
          run_id: "run-linear-conformance",
          attempt_id: "run-linear-conformance:1",
          opts: %{
            linear_client: Fixtures.client_opts(),
            linear_request: Fixtures.request_opts(nil)
          }
        },
        expect: %{
          output: Fixtures.expected_output(capability_id),
          event_types: ["attempt.started", entry.event_type, "attempt.completed"],
          artifact_types: [:tool_output],
          artifact_keys: [
            "linear/run-linear-conformance/run-linear-conformance:1/#{entry.artifact_slug}.term"
          ]
        }
      }
    end)
  end
end
