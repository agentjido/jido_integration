defmodule Jido.Integration.V2.Conformance.Suites.CapabilityContracts do
  @moduledoc false

  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport
  alias Jido.Integration.V2.Manifest

  @spec run(map()) :: SuiteResult.t()
  def run(%{manifest: manifest}) do
    capabilities = Manifest.capabilities(manifest)
    capability_ids = Enum.map(capabilities, & &1.id)
    operation_ids = Enum.map(manifest.operations, & &1.operation_id)
    trigger_ids = Enum.map(manifest.triggers, & &1.trigger_id)

    checks =
      [
        SuiteSupport.check(
          "operations.unique_ids",
          operation_ids == Enum.uniq(operation_ids),
          "operation ids must be unique within a manifest"
        ),
        SuiteSupport.check(
          "triggers.unique_ids",
          trigger_ids == Enum.uniq(trigger_ids),
          "trigger ids must be unique within a manifest"
        ),
        SuiteSupport.check(
          "capabilities.unique_ids",
          capability_ids == Enum.uniq(capability_ids),
          "capability ids must be unique within a manifest"
        ),
        SuiteSupport.check(
          "capabilities.derived_ids_match_authored_specs",
          capability_ids == Enum.sort(operation_ids ++ trigger_ids),
          "derived executable capability ids must match the authored operation and trigger ids"
        )
      ] ++
        Enum.flat_map(capabilities, fn capability ->
          authored_source_checks(capability, manifest)
        end)

    SuiteResult.from_checks(
      :capability_contracts,
      checks,
      "Capabilities publish explicit ids, ownership, and metadata"
    )
  end

  defp authored_source_checks(capability, manifest) do
    operation = SuiteSupport.fetch_operation(manifest, capability.id)
    trigger = SuiteSupport.fetch_trigger(manifest, capability.id)
    source = operation || trigger

    [
      SuiteSupport.check(
        "#{capability.id}.connector_matches_manifest",
        capability.connector == manifest.connector,
        "capability.connector must match manifest.connector"
      ),
      SuiteSupport.check(
        "#{capability.id}.authored_source.present",
        not is_nil(source),
        "each derived capability must map back to an authored operation or trigger"
      ),
      SuiteSupport.check(
        "#{capability.id}.kind.matches_source",
        kind_matches_source?(capability, operation, trigger),
        "derived capability.kind must match the authored source type"
      ),
      SuiteSupport.check(
        "#{capability.id}.runtime_class.matches_source",
        is_nil(source) or capability.runtime_class == source.runtime_class,
        "derived capability.runtime_class must match the authored source"
      ),
      SuiteSupport.check(
        "#{capability.id}.transport_profile.matches_source",
        transport_matches_source?(capability, operation, trigger),
        "derived capability.transport_profile must match the authored source"
      ),
      SuiteSupport.check(
        "#{capability.id}.metadata.map",
        is_map(capability.metadata),
        "capability.metadata must be a map"
      ),
      schema_check(capability, operation, trigger)
    ]
  end

  defp kind_matches_source?(capability, %{} = _operation, nil), do: capability.kind == :operation
  defp kind_matches_source?(capability, nil, %{} = _trigger), do: capability.kind == :trigger
  defp kind_matches_source?(_capability, _operation, _trigger), do: false

  defp transport_matches_source?(capability, %{} = operation, nil) do
    capability.transport_profile == operation.transport_mode
  end

  defp transport_matches_source?(capability, nil, %{} = trigger) do
    capability.transport_profile == trigger.delivery_mode
  end

  defp transport_matches_source?(_capability, _operation, _trigger), do: false

  defp schema_check(capability, %{} = _operation, nil) do
    SuiteSupport.check(
      "#{capability.id}.input_output_schemas.present",
      Map.has_key?(capability.metadata, :input_schema) and
        Map.has_key?(capability.metadata, :output_schema),
      "derived operation capabilities must carry input and output schemas"
    )
  end

  defp schema_check(capability, nil, %{} = _trigger) do
    SuiteSupport.check(
      "#{capability.id}.config_signal_schemas.present",
      Map.has_key?(capability.metadata, :config_schema) and
        Map.has_key?(capability.metadata, :signal_schema),
      "derived trigger capabilities must carry config and signal schemas"
    )
  end

  defp schema_check(capability, _operation, _trigger) do
    SuiteSupport.check(
      "#{capability.id}.schema_projection.present",
      false,
      "derived capability could not be matched to an authored schema source"
    )
  end
end
