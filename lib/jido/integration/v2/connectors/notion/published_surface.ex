defmodule Jido.Integration.V2.Connectors.Notion.PublishedSurface do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.Notion.SchemaContract
  alias Jido.Integration.V2.Contracts

  @spec consumer_surface(String.t()) :: map()
  def consumer_surface("notion.users.get_self") do
    %{mode: :common, normalized_id: "workspace.self", action_name: "workspace_self"}
  end

  def consumer_surface("notion.search.search") do
    %{mode: :common, normalized_id: "content.search", action_name: "content_search"}
  end

  def consumer_surface("notion.pages.create") do
    %{mode: :common, normalized_id: "page.create", action_name: "page_create"}
  end

  def consumer_surface("notion.pages.retrieve") do
    %{mode: :common, normalized_id: "page.fetch", action_name: "page_fetch"}
  end

  def consumer_surface("notion.pages.update") do
    %{mode: :common, normalized_id: "page.update", action_name: "page_update"}
  end

  def consumer_surface("notion.blocks.list_children") do
    %{mode: :common, normalized_id: "block.children.list", action_name: "block_children_list"}
  end

  def consumer_surface("notion.blocks.append_children") do
    %{
      mode: :common,
      normalized_id: "block.children.append",
      action_name: "block_children_append"
    }
  end

  def consumer_surface("notion.data_sources.query") do
    %{mode: :common, normalized_id: "data_source.query", action_name: "data_source_query"}
  end

  def consumer_surface("notion.comments.create") do
    %{mode: :common, normalized_id: "comment.create", action_name: "comment_create"}
  end

  @spec schema_policy(String.t()) :: map()
  def schema_policy(operation_id) when is_binary(operation_id) do
    case SchemaContract.metadata_for(operation_id)[:schema_strategy] do
      :static -> %{input: :defined, output: :defined}
      :late_bound_input -> %{input: :dynamic, output: :defined}
      :late_bound_output -> %{input: :defined, output: :dynamic}
      :late_bound_input_output -> %{input: :dynamic, output: :dynamic}
    end
  end

  @spec input_schema(String.t()) :: Zoi.schema()
  def input_schema("notion.users.get_self"),
    do:
      Contracts.strict_object!([],
        description: "No input is required to fetch the current bot user"
      )

  def input_schema("notion.search.search") do
    Contracts.strict_object!(
      [
        query: Zoi.string() |> Zoi.optional(),
        filter:
          Contracts.strict_object!(
            [
              property: Zoi.string(),
              value: Zoi.string()
            ],
            description: "Optional Notion search object filter"
          )
          |> Zoi.optional(),
        sort:
          Contracts.strict_object!(
            [
              direction: Zoi.string(),
              timestamp: Zoi.string()
            ],
            description: "Optional Notion search sort configuration"
          )
          |> Zoi.optional(),
        start_cursor: Zoi.string() |> Zoi.optional(),
        page_size: Zoi.integer() |> Zoi.optional()
      ],
      description: "Search pages or data sources that are shared with the Notion integration"
    )
  end

  def input_schema("notion.pages.create") do
    Contracts.strict_object!(
      [
        parent:
          Contracts.strict_object!(
            [
              data_source_id: Zoi.string() |> Zoi.optional(),
              page_id: Zoi.string() |> Zoi.optional()
            ],
            description: "Parent reference for the new Notion page"
          ),
        properties:
          Zoi.map(description: "Notion page properties keyed by the parent data source"),
        children:
          Zoi.list(Zoi.map(description: "Optional initial block payload"))
          |> Zoi.optional()
      ],
      description: "Create a Notion page under a page or data source parent"
    )
  end

  def input_schema("notion.pages.retrieve") do
    Contracts.strict_object!(
      [
        page_id: Zoi.string()
      ],
      description: "Lookup a single Notion page by page_id"
    )
  end

  def input_schema("notion.pages.update") do
    Contracts.strict_object!(
      [
        page_id: Zoi.string(),
        archived: Zoi.boolean() |> Zoi.optional(),
        in_trash: Zoi.boolean() |> Zoi.optional(),
        is_locked: Zoi.boolean() |> Zoi.optional(),
        properties: Zoi.map(description: "Page properties to update") |> Zoi.optional(),
        icon: Zoi.map(description: "Optional page icon payload") |> Zoi.optional(),
        cover: Zoi.map(description: "Optional page cover payload") |> Zoi.optional()
      ],
      description: "Update a Notion page and optionally mutate schema-sensitive properties"
    )
  end

  def input_schema("notion.blocks.list_children") do
    Contracts.strict_object!(
      [
        block_id: Zoi.string(),
        start_cursor: Zoi.string() |> Zoi.optional(),
        page_size: Zoi.integer() |> Zoi.optional()
      ],
      description: "List the child blocks of a Notion block"
    )
  end

  def input_schema("notion.blocks.append_children") do
    Contracts.strict_object!(
      [
        block_id: Zoi.string(),
        children: Zoi.list(Zoi.map(description: "Block payload to append")),
        after: Zoi.string() |> Zoi.optional()
      ],
      description: "Append block children under an existing Notion block"
    )
  end

  def input_schema("notion.data_sources.query") do
    Contracts.strict_object!(
      [
        data_source_id: Zoi.string(),
        filter: Zoi.map(description: "Optional data source filter") |> Zoi.optional(),
        sorts:
          Zoi.list(Zoi.map(description: "Optional data source sort descriptor"))
          |> Zoi.optional(),
        start_cursor: Zoi.string() |> Zoi.optional(),
        page_size: Zoi.integer() |> Zoi.optional()
      ],
      description: "Query a Notion data source with provider-native filter and sort payloads"
    )
  end

  def input_schema("notion.comments.create") do
    Contracts.strict_object!(
      [
        parent:
          Contracts.strict_object!(
            [
              page_id: Zoi.string() |> Zoi.optional(),
              block_id: Zoi.string() |> Zoi.optional()
            ],
            description: "Comment parent object"
          ),
        rich_text: Zoi.list(Zoi.map(description: "Rich text segments to publish"))
      ],
      description: "Create a Notion comment on a page or block"
    )
  end

  @spec output_schema(String.t()) :: Zoi.schema()
  def output_schema("notion.users.get_self") do
    Contracts.strict_object!(
      [
        object: Zoi.string(),
        id: Zoi.string(),
        name: Zoi.string() |> Zoi.optional(),
        type: Zoi.string(),
        bot: Zoi.map(description: "Bot ownership and workspace context") |> Zoi.optional()
      ],
      description: "Current bot user identity returned by Notion"
    )
  end

  def output_schema("notion.search.search") do
    list_response_schema(
      Zoi.map(description: "Search result page or data source summary"),
      "Search result page or data source list"
    )
  end

  def output_schema("notion.pages.create") do
    page_response_schema("Created page envelope returned by Notion")
  end

  def output_schema("notion.pages.retrieve") do
    page_response_schema("Retrieved page envelope returned by Notion")
  end

  def output_schema("notion.pages.update") do
    page_response_schema("Updated page envelope returned by Notion")
  end

  def output_schema("notion.blocks.list_children") do
    list_response_schema(
      Zoi.map(description: "Child block summary"),
      "Child block list returned by Notion"
    )
  end

  def output_schema("notion.blocks.append_children") do
    Contracts.strict_object!(
      [
        object: Zoi.string(),
        results: Zoi.list(Zoi.map(description: "Appended child block summary"))
      ],
      description: "Append-children result returned by Notion"
    )
  end

  def output_schema("notion.data_sources.query") do
    list_response_schema(
      Zoi.map(description: "Queried page result"),
      "Data source query page list"
    )
  end

  def output_schema("notion.comments.create") do
    Contracts.strict_object!(
      [
        object: Zoi.string(),
        id: Zoi.string(),
        discussion_id: Zoi.string(),
        parent: Zoi.map(description: "Comment parent reference"),
        created_by: Zoi.map(description: "Comment author envelope") |> Zoi.optional()
      ],
      description: "Created Notion comment envelope"
    )
  end

  defp list_response_schema(item_schema, description) do
    Contracts.strict_object!(
      [
        object: Zoi.string(),
        results: Zoi.list(item_schema),
        next_cursor: Zoi.string() |> Zoi.nullish(),
        has_more: Zoi.boolean()
      ],
      description: description
    )
  end

  defp page_response_schema(description) do
    Contracts.strict_object!(
      [
        object: Zoi.string(),
        id: Zoi.string(),
        archived: Zoi.boolean() |> Zoi.optional(),
        in_trash: Zoi.boolean() |> Zoi.optional(),
        url: Zoi.string() |> Zoi.optional(),
        parent: Zoi.map(description: "Parent page, database, or data source reference"),
        properties:
          Zoi.map(description: "Provider-shaped page properties")
          |> Zoi.optional(),
        last_edited_by: Zoi.map(description: "Last editor envelope") |> Zoi.optional()
      ],
      description: description
    )
  end
end
