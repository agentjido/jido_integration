defmodule Jido.Integration.V2.Connectors.AmpTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.Amp
  alias Jido.Integration.V2.Connectors.Amp.Conformance

  test "publishes Amp CLI governed operation manifest" do
    manifest = Amp.manifest()
    operations = Map.new(manifest.operations, &{&1.operation_id, &1})

    assert manifest.connector == "amp"

    assert Map.keys(operations) == [
             "amp.command.run",
             "amp.mcp.status",
             "amp.permissions.assert",
             "amp.stream.run"
           ]

    command = Map.fetch!(operations, "amp.command.run")
    assert command.runtime.provider == :amp
    assert command.runtime_class == :direct
    assert command.metadata.tool_category == :provider_native_tool
    assert command.metadata.native_auth_assertion_required == true
    assert command.metadata.connector_binding_required == true
    assert command.metadata.credential_lease_required == true
    assert command.metadata.redaction == :ref_only

    stream = Map.fetch!(operations, "amp.stream.run")
    assert stream.runtime_class == :stream
  end

  test "registers official Amp connector lane with ref-only identity" do
    assert {:ok, entry} = Amp.registry_entry()

    assert entry.provider_ref == "provider://amp"
    assert entry.provider_family == "cli"
    assert entry.connector_category == :official_connector
    assert entry.connector_binding_ref == "connector-binding://tenant-1/amp/cli"
    assert entry.package_path == "connectors/amp"
    assert entry.binding_shape.requires_native_auth_assertion_ref == true
    assert entry.product_boundary.standalone_preserved == true
  end

  test "publishes bounded tool contracts and conformance fixture refs" do
    contracts = Amp.tool_contracts()

    assert Enum.map(contracts, & &1.category) == [
             :provider_native_tool,
             :connector_tool,
             :read_only_observation
           ]

    assert [
             %{
               capability_id: "amp.command.run",
               expect: %{refs: refs}
             }
           ] = Conformance.fixtures()

    assert refs.native_auth_assertion_ref == "native-auth-assertion://amp/fixture"
    refute inspect(refs) =~ "AMP_API_KEY"
  end
end
