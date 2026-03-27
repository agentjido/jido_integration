defmodule Jido.Integration.V2.Connectors.NotionTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2, as: V2
  alias Jido.Integration.V2.Connectors.Notion
  alias Jido.Integration.V2.Connectors.Notion.Operation
  alias Jido.Integration.V2.Connectors.Notion.OperationCatalog
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.TriggerSpec

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
  @published_trigger_ids ["notion.pages.recently_edited"]
  @schema_contracts %{
    "notion.users.get_self" => %{
      strategy: :static,
      context_source: :none,
      slots: []
    },
    "notion.search.search" => %{
      strategy: :static,
      context_source: :none,
      slots: []
    },
    "notion.pages.create" => %{
      strategy: :late_bound_input,
      context_source: :parent_data_source,
      slots: [
        %{
          surface: :input,
          path: ["properties"],
          kind: :data_source_properties,
          source: :parent_data_source
        }
      ]
    },
    "notion.pages.retrieve" => %{
      strategy: :late_bound_output,
      context_source: :page_parent_data_source,
      slots: [
        %{
          surface: :output,
          path: ["properties"],
          kind: :data_source_properties,
          source: :page_parent_data_source
        }
      ]
    },
    "notion.pages.update" => %{
      strategy: :late_bound_input_output,
      context_source: :page_parent_data_source,
      slots: [
        %{
          surface: :input,
          path: ["properties"],
          kind: :data_source_properties,
          source: :page_parent_data_source
        },
        %{
          surface: :output,
          path: ["properties"],
          kind: :data_source_properties,
          source: :page_parent_data_source
        }
      ]
    },
    "notion.blocks.list_children" => %{
      strategy: :static,
      context_source: :none,
      slots: []
    },
    "notion.blocks.append_children" => %{
      strategy: :static,
      context_source: :none,
      slots: []
    },
    "notion.data_sources.query" => %{
      strategy: :late_bound_input_output,
      context_source: :data_source,
      slots: [
        %{
          surface: :input,
          path: ["filter"],
          kind: :data_source_filter,
          source: :data_source
        },
        %{
          surface: :input,
          path: ["sorts"],
          kind: :data_source_sorts,
          source: :data_source
        },
        %{
          surface: :output,
          path: ["results", "*", "properties"],
          kind: :data_source_properties,
          source: :data_source
        }
      ]
    },
    "notion.comments.create" => %{
      strategy: :static,
      context_source: :none,
      slots: []
    }
  }

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

    assert Enum.map(manifest.capabilities, & &1.id) ==
             Enum.sort(@published_capability_ids ++ @published_trigger_ids)

    operation_capabilities = Enum.filter(manifest.capabilities, &(&1.kind == :operation))

    Enum.each(operation_capabilities, fn capability ->
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

    assert trigger_capability =
             Enum.find(manifest.capabilities, &(&1.id == "notion.pages.recently_edited"))

    assert trigger_capability.kind == :trigger
    assert trigger_capability.transport_profile == :poll
    assert trigger_capability.metadata.checkpoint.strategy == :timestamp_cursor
    assert trigger_capability.metadata.dedupe.strategy == :page_id_last_edited_time

    Enum.each(manifest.operations, fn operation ->
      assert operation.consumer_surface.mode == :common
      assert is_binary(operation.consumer_surface.normalized_id)
      assert is_binary(operation.consumer_surface.action_name)
      assert operation.schema_policy.input in [:defined, :dynamic]
      assert operation.schema_policy.output in [:defined, :dynamic]
      refute Map.has_key?(operation.schema_policy, :justification)
    end)

    assert [trigger] = manifest.triggers
    assert trigger.trigger_id == "notion.pages.recently_edited"
    assert TriggerSpec.common_consumer_surface?(trigger)
    assert trigger.delivery_mode == :poll
    assert trigger.checkpoint.strategy == :timestamp_cursor
    assert trigger.dedupe.strategy == :page_id_last_edited_time
  end

  test "registers through the public facade and exposes deterministic lookup by connector and capability id" do
    assert :ok = V2.register_connector(Notion)

    assert {:ok, connector} = V2.fetch_connector("notion")
    assert connector.connector == "notion"

    assert Enum.map(V2.connectors(), & &1.connector) == ["notion"]

    assert Enum.map(V2.capabilities(), & &1.id) ==
             Enum.sort(@published_capability_ids ++ @published_trigger_ids)

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

  test "classifies the published A0 slice for static versus late-bound schema behavior" do
    manifest = Notion.manifest()

    operations = Map.new(manifest.operations, &{&1.operation_id, &1})
    capabilities = Map.new(manifest.capabilities, &{&1.id, &1})

    Enum.each(@schema_contracts, fn {operation_id, expected} ->
      operation = Map.fetch!(operations, operation_id)
      capability = Map.fetch!(capabilities, operation_id)

      assert OperationSpec.schema_strategy(operation) == expected.strategy
      assert OperationSpec.schema_context_source(operation) == expected.context_source
      assert OperationSpec.schema_slots(operation) == expected.slots

      assert capability.metadata.schema_strategy == expected.strategy
      assert capability.metadata.schema_context_source == expected.context_source
      assert capability.metadata.schema_slots == expected.slots
    end)
  end

  test "normalizes inventory roots for direct inputs and the connector-owned artifact" do
    assert OperationCatalog.inventory_path("/tmp/notion_sdk_priv") ==
             "/tmp/notion_sdk_priv/upstream/parity_inventory.json"

    assert OperationCatalog.inventory_path(~c"/tmp/notion_sdk_priv") ==
             "/tmp/notion_sdk_priv/upstream/parity_inventory.json"

    assert OperationCatalog.inventory_path()
           |> String.ends_with?("/connectors/notion/priv/upstream/parity_inventory.json")

    assert File.exists?(OperationCatalog.inventory_path())
  end
end
