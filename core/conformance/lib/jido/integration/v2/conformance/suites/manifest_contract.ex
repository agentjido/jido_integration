defmodule Jido.Integration.V2.Conformance.Suites.ManifestContract do
  @moduledoc false

  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport

  @spec run(map()) :: SuiteResult.t()
  def run(%{manifest: manifest}) do
    capability_ids = Enum.map(manifest.capabilities, & &1.id)

    checks = [
      SuiteSupport.check(
        "manifest.connector.present",
        is_binary(manifest.connector) and String.trim(manifest.connector) != "",
        "manifest.connector must be a non-empty string"
      ),
      SuiteSupport.check(
        "manifest.capabilities.present",
        is_list(manifest.capabilities) and manifest.capabilities != [],
        "connector manifests must declare at least one capability"
      ),
      SuiteSupport.check(
        "manifest.metadata.map",
        is_map(manifest.metadata),
        "manifest.metadata must be a map"
      ),
      SuiteSupport.check(
        "manifest.capability_order.deterministic",
        capability_ids == Enum.sort(capability_ids),
        "manifest capabilities must be emitted in deterministic id order"
      )
    ]

    SuiteResult.from_checks(
      :manifest_contract,
      checks,
      "Manifest and connector identity stay deterministic"
    )
  end
end
