defmodule Jido.Integration.V2.Conformance.Suites.CapabilityContracts do
  @moduledoc false

  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport

  @spec run(map()) :: SuiteResult.t()
  def run(%{manifest: manifest}) do
    capability_ids = Enum.map(manifest.capabilities, & &1.id)

    checks =
      [
        SuiteSupport.check(
          "capabilities.unique_ids",
          capability_ids == Enum.uniq(capability_ids),
          "capability ids must be unique within a manifest"
        )
      ] ++
        Enum.flat_map(manifest.capabilities, fn capability ->
          [
            SuiteSupport.check(
              "#{capability.id}.connector_matches_manifest",
              capability.connector == manifest.connector,
              "capability.connector must match manifest.connector"
            ),
            SuiteSupport.check(
              "#{capability.id}.kind.atom",
              is_atom(capability.kind),
              "capability.kind must be an atom"
            ),
            SuiteSupport.check(
              "#{capability.id}.transport_profile.atom",
              is_atom(capability.transport_profile),
              "capability.transport_profile must be an atom"
            ),
            SuiteSupport.check(
              "#{capability.id}.metadata.map",
              is_map(capability.metadata),
              "capability.metadata must be a map"
            )
          ]
        end)

    SuiteResult.from_checks(
      :capability_contracts,
      checks,
      "Capabilities publish explicit ids, ownership, and metadata"
    )
  end
end
