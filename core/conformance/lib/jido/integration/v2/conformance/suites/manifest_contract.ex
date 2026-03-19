defmodule Jido.Integration.V2.Conformance.Suites.ManifestContract do
  @moduledoc false

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport

  @spec run(map()) :: SuiteResult.t()
  def run(%{manifest: manifest}) do
    manifest_map = Map.from_struct(manifest)
    connector = Map.get(manifest_map, :connector)
    operations = Map.get(manifest_map, :operations, [])
    triggers = Map.get(manifest_map, :triggers, [])
    capabilities = Map.get(manifest_map, :capabilities, [])
    capability_ids = Enum.map(capabilities, &Map.get(&1, :id))
    operation_ids = Enum.map(operations, &Map.get(&1, :operation_id))
    trigger_ids = Enum.map(triggers, &Map.get(&1, :trigger_id))
    derived_runtime_families = derive_runtime_families(operations, triggers)
    runtime_families = Map.get(manifest_map, :runtime_families, [])
    auth = Map.get(manifest_map, :auth)
    missing_scopes = missing_requested_scopes(auth, operations, triggers)
    missing_trigger_secrets = missing_trigger_secrets(auth, triggers)

    checks = [
      SuiteSupport.check(
        "manifest.connector.present",
        is_binary(connector) and String.trim(connector) != "",
        "manifest.connector must be a non-empty string"
      ),
      SuiteSupport.check(
        "manifest.auth.present",
        match?(%AuthSpec{}, Map.get(manifest_map, :auth)),
        "manifest.auth must be an AuthSpec"
      ),
      SuiteSupport.check(
        "manifest.catalog.present",
        match?(%CatalogSpec{}, Map.get(manifest_map, :catalog)),
        "manifest.catalog must be a CatalogSpec"
      ),
      SuiteSupport.check(
        "manifest.authored_entries.present",
        operation_ids != [] or trigger_ids != [],
        "connector manifests must declare at least one authored operation or trigger"
      ),
      SuiteSupport.check(
        "manifest.auth.requested_scopes.cover_required",
        missing_scopes == [],
        "manifest.auth.requested_scopes must cover all authored operation and trigger required_scopes"
      ),
      SuiteSupport.check(
        "manifest.auth.secret_names.cover_trigger_secrets",
        missing_trigger_secrets == [],
        "manifest.auth.secret_names must declare every authored trigger verification secret_name and secret_requirements entry"
      ),
      SuiteSupport.check(
        "manifest.operations.deterministic",
        operation_ids == Enum.sort(operation_ids),
        "manifest operations must be emitted in deterministic id order"
      ),
      SuiteSupport.check(
        "manifest.triggers.deterministic",
        trigger_ids == Enum.sort(trigger_ids),
        "manifest triggers must be emitted in deterministic id order"
      ),
      SuiteSupport.check(
        "manifest.runtime_families.match_specs",
        runtime_families == derived_runtime_families,
        "manifest runtime_families must match the authored operation and trigger specs"
      ),
      SuiteSupport.check(
        "manifest.capability_order.deterministic",
        capability_ids == Enum.sort(capability_ids),
        "manifest capabilities must be emitted in deterministic id order"
      ),
      SuiteSupport.check(
        "manifest.metadata.map",
        is_map(Map.get(manifest_map, :metadata)),
        "manifest.metadata must be a map"
      )
    ]

    SuiteResult.from_checks(
      :manifest_contract,
      checks,
      "Manifest and connector identity stay deterministic"
    )
  end

  defp derive_runtime_families(operations, triggers) do
    (Enum.map(operations, &Map.get(&1, :runtime_class)) ++
       Enum.map(triggers, &Map.get(&1, :runtime_class)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp missing_requested_scopes(%AuthSpec{} = auth, operations, triggers) do
    (Enum.flat_map(operations, &required_scopes(Map.get(&1, :permissions, %{}))) ++
       Enum.flat_map(triggers, &required_scopes(Map.get(&1, :permissions, %{}))))
    |> Enum.uniq()
    |> Enum.sort()
    |> Kernel.--(Enum.uniq(auth.requested_scopes))
  end

  defp missing_requested_scopes(_auth, _operations, _triggers), do: [:invalid_auth]

  defp missing_trigger_secrets(%AuthSpec{} = auth, triggers) do
    triggers
    |> Enum.flat_map(&trigger_secret_names/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Kernel.--(Enum.uniq(auth.secret_names))
  end

  defp missing_trigger_secrets(_auth, _triggers), do: [:invalid_auth]

  defp required_scopes(permissions) do
    permissions
    |> SuiteSupport.fetch(:required_scopes, [])
    |> normalize_string_list()
  end

  defp trigger_secret_names(trigger) do
    verification_secret_name =
      trigger
      |> Map.get(:verification, %{})
      |> SuiteSupport.fetch(:secret_name)
      |> normalize_optional_secret_name()

    secret_requirements =
      trigger
      |> Map.get(:secret_requirements, [])
      |> normalize_string_list()

    secret_requirements ++ verification_secret_name
  end

  defp normalize_optional_secret_name(nil), do: []
  defp normalize_optional_secret_name(secret_name), do: normalize_string_list([secret_name])

  defp normalize_string_list(values) when is_list(values) do
    Enum.map(values, &to_string/1)
  end

  defp normalize_string_list(_values), do: []
end
