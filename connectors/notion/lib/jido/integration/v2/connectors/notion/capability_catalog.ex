defmodule Jido.Integration.V2.Connectors.Notion.CapabilityCatalog do
  @moduledoc false

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Connectors.Notion.Operation

  @notion_sdk_source_path Path.expand("../../../../../../../../../notion_sdk", __DIR__)
  @connector_id "notion"
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
          capability_id: String.t(),
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
    Enum.map(@published_capability_ids, &fetch!/1)
  end

  @spec fetch!(String.t()) :: entry()
  def fetch!(capability_id) when is_binary(capability_id) do
    Enum.find(entries(), &(&1.capability_id == capability_id)) ||
      raise KeyError, key: capability_id, term: __MODULE__
  end

  @spec published_capabilities() :: [Capability.t()]
  def published_capabilities do
    published_entries()
    |> Enum.map(&capability/1)
    |> Enum.sort_by(& &1.id)
  end

  defp capability(entry) do
    Capability.new!(%{
      id: entry.capability_id,
      connector: @connector_id,
      runtime_class: :direct,
      kind: :operation,
      transport_profile: :sdk,
      handler: Operation,
      metadata: %{
        sdk_module: entry.sdk_module,
        sdk_function: entry.sdk_function,
        permission_bundle: entry.permission_bundle,
        required_scopes: entry.permission_bundle,
        event_suffix: entry.event_suffix,
        artifact_slug: entry.artifact_slug,
        rollout_phase: entry.rollout_phase,
        upstream: %{
          method: entry.method,
          path: entry.path,
          reference_page: entry.reference_page
        },
        policy:
          put_in(
            @policy_defaults,
            [:sandbox, :allowed_tools],
            [entry.capability_id]
          )
      }
    })
  end

  defp build_entry(operation) do
    module_name = Map.fetch!(operation, "module")
    function_name = Map.fetch!(operation, "function")
    key = module_name <> "." <> function_name
    capability_suffix = capability_namespace(module_name) <> ".#{function_name}"
    capability_id = @connector_id <> "." <> capability_suffix

    %{
      capability_id: capability_id,
      sdk_module: Module.concat(NotionSDK, module_name),
      sdk_function: function_atom(function_name),
      permission_bundle: Map.fetch!(@permission_overrides, key),
      event_suffix: capability_suffix,
      artifact_slug: String.replace(capability_suffix, ".", "_"),
      rollout_phase: rollout_phase(capability_id),
      published?: capability_id in @published_capability_ids,
      method: Map.fetch!(operation, "method"),
      path: Map.fetch!(operation, "path"),
      reference_page: Map.get(operation, "reference_page")
    }
  end

  defp rollout_phase("notion.oauth." <> _rest), do: :auth_control
  defp rollout_phase(capability_id) when capability_id in @published_capability_ids, do: :a0
  defp rollout_phase(_capability_id), do: :a1

  defp capability_namespace("OAuth"), do: "oauth"
  defp capability_namespace(module_name), do: Macro.underscore(module_name)

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

  @spec inventory_path(String.t() | charlist()) :: String.t()
  def inventory_path(priv_dir \\ :code.priv_dir(:notion_sdk))

  def inventory_path({:error, _reason}) do
    notion_sdk_priv_dir()
    |> inventory_path()
  end

  def inventory_path(priv_dir) when is_binary(priv_dir),
    do: Path.join(priv_dir, "upstream/parity_inventory.json")

  def inventory_path(priv_dir) when is_list(priv_dir),
    do: inventory_path(List.to_string(priv_dir))

  defp notion_sdk_priv_dir do
    case Mix.Project.get() do
      nil ->
        Path.join(@notion_sdk_source_path, "priv")

      _project ->
        Mix.Project.deps_paths()
        |> Map.get(:notion_sdk, @notion_sdk_source_path)
        |> Path.join("priv")
    end
  end
end
