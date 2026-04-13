defmodule Jido.Integration.V2.Connectors.Notion.TriggerCatalog do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.Notion.RecentPageEditsTrigger
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.TriggerSpec

  @trigger_id "notion.pages.recently_edited"
  @signal_type "notion.page.recently_edited"
  @signal_source "/ingress/poll/notion/pages.recently_edited"

  @spec published_triggers() :: [TriggerSpec.t()]
  def published_triggers do
    [
      TriggerSpec.new!(%{
        trigger_id: @trigger_id,
        name: "pages_recently_edited",
        display_name: "Pages recently edited",
        description:
          "Polls Notion Search for recently edited pages and emits normalized page signals",
        runtime_class: :direct,
        delivery_mode: :poll,
        polling: %{default_interval_ms: 60_000, min_interval_ms: 5_000, jitter: false},
        handler: RecentPageEditsTrigger,
        config_schema:
          Contracts.strict_object!(
            [
              page_size: Zoi.integer() |> Zoi.default(10)
            ],
            description: "Polling configuration for the recent page edits sensor"
          ),
        signal_schema:
          Contracts.strict_object!(
            [
              page_id: Zoi.string(),
              last_edited_time: Zoi.string(),
              title: Zoi.string(),
              url: Zoi.string()
            ],
            description: "Normalized signal for one Notion page edit"
          ),
        permissions: %{required_scopes: ["notion.content.read"]},
        checkpoint: %{
          strategy: :timestamp_cursor,
          field: "last_edited_time",
          partition_key: "workspace"
        },
        dedupe: %{
          strategy: :page_id_last_edited_time,
          fields: ["page_id", "last_edited_time"]
        },
        verification: %{},
        policy: %{
          environment: %{allowed: [:prod, :staging]},
          sandbox: %{
            level: :standard,
            egress: :restricted,
            approvals: :auto,
            allowed_tools: [@trigger_id]
          }
        },
        consumer_surface: %{
          mode: :common,
          normalized_id: "page.recently_edited",
          sensor_name: "page_recently_edited"
        },
        schema_policy: %{config: :defined, signal: :defined},
        jido: %{
          sensor: %{
            name: "notion_page_recently_edited_sensor",
            signal_type: @signal_type,
            signal_source: @signal_source
          }
        },
        metadata: %{
          poll_basis: :search_api,
          search_filter: %{"property" => "object", "value" => "page"},
          search_sort: %{"timestamp" => "last_edited_time", "direction" => "descending"}
        }
      })
    ]
  end
end
