defmodule Jido.Integration.V2.Connectors.NotionTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2, as: V2
  alias Jido.Integration.V2.Connectors.Notion
  alias Jido.Integration.V2.Connectors.Notion.Operation
  alias Jido.Integration.V2.Connectors.Notion.OperationCatalog

  @published_capability_ids [
    "notion.users.get_self",
    "notion.search.search",
    "notion.pages.create",
    "notion.pages.retrieve",
    "notion.pages.update",
    "notion.blocks.list_children",
    "notion.blocks.append_children",
    "notion.data_sources.query",
    "notion.comments.create"
  ]

  setup do
    V2.reset!()
    :ok
  end

  test "publishes the A0 direct catalog slice as authored operation specs plus derived capabilities" do
    manifest = Notion.manifest()

    assert manifest.connector == "notion"
    assert manifest.auth.binding_kind == :connection_id
    assert manifest.auth.auth_type == :oauth2
    assert manifest.catalog.display_name == "Notion"
    assert manifest.catalog.publication == :public
    assert manifest.runtime_families == [:direct]

    assert Enum.map(manifest.operations, & &1.operation_id) ==
             Enum.sort(@published_capability_ids)

    assert Enum.map(manifest.capabilities, & &1.id) == Enum.sort(@published_capability_ids)

    Enum.each(manifest.capabilities, fn capability ->
      assert capability.runtime_class == :direct
      assert capability.kind == :operation
      assert capability.transport_profile == :sdk
      assert capability.handler == Operation
      assert capability.metadata.sdk_module |> is_atom()
      assert capability.metadata.sdk_function |> is_atom()
      assert capability.metadata.permission_bundle |> is_list()
      assert capability.metadata.input_schema |> is_struct()
      assert capability.metadata.output_schema |> is_struct()
      assert capability.metadata.rollout_phase == :a0
      assert capability.metadata.event_suffix |> is_binary()
      assert capability.metadata.artifact_slug |> is_binary()
      assert capability.metadata.required_scopes == capability.metadata.permission_bundle
      assert capability.metadata.jido.action.name |> is_binary()
      assert capability.metadata.policy.environment.allowed == [:prod, :staging]
      assert capability.metadata.policy.sandbox.level == :standard
      assert capability.metadata.policy.sandbox.egress == :restricted
      assert capability.metadata.policy.sandbox.approvals == :auto
      assert capability.metadata.policy.sandbox.allowed_tools == [capability.id]
    end)
  end

  test "registers through the public facade and exposes deterministic lookup by connector and capability id" do
    assert :ok = V2.register_connector(Notion)

    assert {:ok, connector} = V2.fetch_connector("notion")
    assert connector.connector == "notion"

    assert Enum.map(V2.connectors(), & &1.connector) == ["notion"]
    assert Enum.map(V2.capabilities(), & &1.id) == Enum.sort(@published_capability_ids)

    assert {:ok, capability} = V2.fetch_capability("notion.pages.retrieve")
    assert capability.handler == Operation
    assert capability.metadata.sdk_module == NotionSDK.Pages
    assert capability.metadata.sdk_function == :retrieve
  end

  test "builds one authored operation catalog from the provider inventory and keeps OAuth control unpublished" do
    entries = OperationCatalog.entries()

    assert Enum.any?(entries, &(&1.operation_id == "notion.oauth.token"))
    assert Enum.any?(entries, &(&1.operation_id == "notion.file_uploads.send"))

    oauth_entry = OperationCatalog.fetch!("notion.oauth.token")
    assert oauth_entry.sdk_module == NotionSDK.OAuth
    assert oauth_entry.sdk_function == :token
    refute oauth_entry.published?

    assert Enum.map(OperationCatalog.published_entries(), & &1.operation_id) ==
             @published_capability_ids

    assert Enum.all?(entries, fn entry ->
             assert Code.ensure_loaded?(entry.sdk_module)
             function_exported?(entry.sdk_module, entry.sdk_function, 2)
           end)
  end

  test "normalizes notion_sdk priv dirs for package and root-task loading" do
    assert OperationCatalog.inventory_path("/tmp/notion_sdk_priv") ==
             "/tmp/notion_sdk_priv/upstream/parity_inventory.json"

    assert OperationCatalog.inventory_path(~c"/tmp/notion_sdk_priv") ==
             "/tmp/notion_sdk_priv/upstream/parity_inventory.json"

    assert OperationCatalog.inventory_path({:error, :bad_name}) ==
             Mix.Project.deps_paths()
             |> Map.fetch!(:notion_sdk)
             |> Path.join("priv/upstream/parity_inventory.json")
  end
end
