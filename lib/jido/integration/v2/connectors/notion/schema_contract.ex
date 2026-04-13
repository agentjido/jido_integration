defmodule Jido.Integration.V2.Connectors.Notion.SchemaContract do
  @moduledoc false

  @schema_contracts %{
    "notion.users.get_self" => %{
      schema_strategy: :static,
      schema_context_source: :none,
      schema_slots: []
    },
    "notion.search.search" => %{
      schema_strategy: :static,
      schema_context_source: :none,
      schema_slots: []
    },
    "notion.pages.create" => %{
      schema_strategy: :late_bound_input,
      schema_context_source: :parent_data_source,
      schema_slots: [
        %{
          surface: :input,
          path: ["properties"],
          kind: :data_source_properties,
          source: :parent_data_source
        }
      ]
    },
    "notion.pages.retrieve" => %{
      schema_strategy: :late_bound_output,
      schema_context_source: :page_parent_data_source,
      schema_slots: [
        %{
          surface: :output,
          path: ["properties"],
          kind: :data_source_properties,
          source: :page_parent_data_source
        }
      ]
    },
    "notion.pages.update" => %{
      schema_strategy: :late_bound_input_output,
      schema_context_source: :page_parent_data_source,
      schema_slots: [
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
      schema_strategy: :static,
      schema_context_source: :none,
      schema_slots: []
    },
    "notion.blocks.append_children" => %{
      schema_strategy: :static,
      schema_context_source: :none,
      schema_slots: []
    },
    "notion.data_sources.query" => %{
      schema_strategy: :late_bound_input_output,
      schema_context_source: :data_source,
      schema_slots: [
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
      schema_strategy: :static,
      schema_context_source: :none,
      schema_slots: []
    }
  }

  @spec metadata_for(String.t()) :: map()
  def metadata_for(operation_id) when is_binary(operation_id) do
    Map.get(@schema_contracts, operation_id, %{})
  end
end
