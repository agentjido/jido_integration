defmodule Jido.Integration.V2.Connectors.Notion.OperationCatalog do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.Notion.Operation
  alias Jido.Integration.V2.Connectors.Notion.SchemaContract
  alias Jido.Integration.V2.OperationSpec

  @connector_id "notion"
  @published_operation_ids [
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
  @policy_defaults %{
    environment: %{allowed: [:prod, :staging]},
    sandbox: %{
      level: :standard,
      egress: :restricted,
      approvals: :auto
    }
  }
  @permission_overrides %{
    "Users.get_self" => ["notion.identity.self"],
    "Users.retrieve" => ["notion.user.read"],
    "Users.list" => ["notion.user.read"],
    "Search.search" => ["notion.content.read"],
    "Pages.create" => ["notion.content.insert"],
    "Pages.retrieve" => ["notion.content.read"],
    "Pages.update" => ["notion.content.update"],
    "Pages.move" => ["notion.content.update"],
    "Pages.retrieve_property" => ["notion.content.read"],
    "Pages.retrieve_markdown" => ["notion.content.read"],
    "Pages.update_markdown" => ["notion.content.update"],
    "Blocks.retrieve" => ["notion.content.read"],
    "Blocks.update" => ["notion.content.update"],
    "Blocks.delete" => ["notion.content.update"],
    "Blocks.list_children" => ["notion.content.read"],
    "Blocks.append_children" => ["notion.content.insert"],
    "DataSources.retrieve" => ["notion.content.read"],
    "DataSources.update" => ["notion.content.update"],
    "DataSources.query" => ["notion.content.read"],
    "DataSources.create" => ["notion.content.insert"],
    "DataSources.list_templates" => ["notion.content.read"],
    "Databases.retrieve" => ["notion.content.read"],
    "Databases.update" => ["notion.content.update"],
    "Databases.create" => ["notion.content.insert"],
    "Comments.create" => ["notion.comment.insert"],
    "Comments.list" => ["notion.comment.read"],
    "Comments.retrieve" => ["notion.comment.read"],
    "FileUploads.create" => ["notion.file_upload.write"],
    "FileUploads.send" => ["notion.file_upload.write"],
    "FileUploads.complete" => ["notion.file_upload.write"],
    "FileUploads.list" => ["notion.file_upload.write"],
    "FileUploads.retrieve" => ["notion.file_upload.write"],
    "OAuth.token" => [],
    "OAuth.revoke" => [],
    "OAuth.introspect" => []
  }

  @type entry :: %{
          artifact_slug: String.t(),
          operation_id: String.t(),
          event_suffix: String.t(),
          method: String.t(),
          path: String.t(),
          permission_bundle: [String.t()],
          published?: boolean(),
          reference_page: String.t() | nil,
          rollout_phase: atom(),
          sdk_function: atom(),
          sdk_module: module()
        }

  @spec entries() :: [entry()]
  def entries do
    inventory()
    |> Enum.map(&build_entry/1)
  end

  @spec published_entries() :: [entry()]
  def published_entries do
    Enum.map(@published_operation_ids, &fetch!/1)
  end

  @spec fetch!(String.t()) :: entry()
  def fetch!(operation_id) when is_binary(operation_id) do
    Enum.find(entries(), &(&1.operation_id == operation_id)) ||
      raise KeyError, key: operation_id, term: __MODULE__
  end

  @spec published_operations() :: [OperationSpec.t()]
  def published_operations do
    published_entries()
    |> Enum.map(&operation_spec/1)
    |> Enum.sort_by(& &1.operation_id)
  end

  defp operation_spec(entry) do
    OperationSpec.new!(%{
      operation_id: entry.operation_id,
      name: entry.event_suffix,
      display_name: display_name(entry.event_suffix),
      description: "Connector-local Notion runtime capability for #{entry.operation_id}",
      runtime_class: :direct,
      transport_mode: :sdk,
      handler: Operation,
      input_schema: Zoi.map(description: "Input payload for #{entry.operation_id}"),
      output_schema: Zoi.map(description: "Output payload for #{entry.operation_id}"),
      permissions: %{
        permission_bundle: entry.permission_bundle,
        required_scopes: entry.permission_bundle
      },
      policy:
        put_in(
          @policy_defaults,
          [:sandbox, :allowed_tools],
          [entry.operation_id]
        ),
      upstream: %{
        method: entry.method,
        path: entry.path,
        reference_page: entry.reference_page
      },
      consumer_surface: %{
        mode: :connector_local,
        reason:
          "Notion runtime capabilities stay connector-local until a normalized common consumer surface exists"
      },
      schema_policy: %{
        input: :passthrough,
        output: :passthrough,
        justification:
          "Published Notion runtime capabilities intentionally preserve the SDK-shaped payload boundary while wrapper parity is deferred"
      },
      jido: %{
        action: %{
          name: String.replace(entry.operation_id, ".", "_")
        }
      },
      metadata:
        Map.merge(
          %{
            sdk_module: entry.sdk_module,
            sdk_function: entry.sdk_function,
            event_suffix: entry.event_suffix,
            artifact_slug: entry.artifact_slug,
            rollout_phase: entry.rollout_phase
          },
          SchemaContract.metadata_for(entry.operation_id)
        )
    })
  end

  defp build_entry(operation) do
    module_name = Map.fetch!(operation, "module")
    function_name = Map.fetch!(operation, "function")
    key = module_name <> "." <> function_name
    operation_suffix = operation_namespace(module_name) <> ".#{function_name}"
    operation_id = @connector_id <> "." <> operation_suffix

    %{
      operation_id: operation_id,
      sdk_module: Module.concat(NotionSDK, module_name),
      sdk_function: function_atom(function_name),
      permission_bundle: Map.fetch!(@permission_overrides, key),
      event_suffix: operation_suffix,
      artifact_slug: String.replace(operation_suffix, ".", "_"),
      rollout_phase: rollout_phase(operation_id),
      published?: operation_id in @published_operation_ids,
      method: Map.fetch!(operation, "method"),
      path: Map.fetch!(operation, "path"),
      reference_page: Map.get(operation, "reference_page")
    }
  end

  defp rollout_phase("notion.oauth." <> _rest), do: :auth_control
  defp rollout_phase(operation_id) when operation_id in @published_operation_ids, do: :a0
  defp rollout_phase(_operation_id), do: :a1

  defp operation_namespace("OAuth"), do: "oauth"
  defp operation_namespace(module_name), do: Macro.underscore(module_name)

  defp function_atom("append_children"), do: :append_children
  defp function_atom("complete"), do: :complete
  defp function_atom("create"), do: :create
  defp function_atom("delete"), do: :delete
  defp function_atom("get_self"), do: :get_self
  defp function_atom("introspect"), do: :introspect
  defp function_atom("list"), do: :list
  defp function_atom("list_children"), do: :list_children
  defp function_atom("list_templates"), do: :list_templates
  defp function_atom("move"), do: :move
  defp function_atom("query"), do: :query
  defp function_atom("refresh_token"), do: :refresh_token
  defp function_atom("retrieve"), do: :retrieve
  defp function_atom("retrieve_markdown"), do: :retrieve_markdown
  defp function_atom("retrieve_property"), do: :retrieve_property
  defp function_atom("revoke"), do: :revoke
  defp function_atom("search"), do: :search
  defp function_atom("send"), do: :send
  defp function_atom("token"), do: :token
  defp function_atom("update"), do: :update
  defp function_atom("update_markdown"), do: :update_markdown

  defp inventory do
    inventory_path()
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("operations")
  end

  @spec inventory_path(String.t() | charlist() | {:error, atom()}) :: String.t()
  def inventory_path(priv_dir \\ :code.priv_dir(:notion_sdk))

  def inventory_path({:error, reason}),
    do: raise("notion_sdk priv dir unavailable: #{inspect(reason)}")

  def inventory_path(priv_dir) when is_binary(priv_dir),
    do: Path.join(priv_dir, "upstream/parity_inventory.json")

  def inventory_path(priv_dir) when is_list(priv_dir),
    do: inventory_path(List.to_string(priv_dir))

  defp display_name(event_suffix) do
    event_suffix
    |> String.split(".")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
