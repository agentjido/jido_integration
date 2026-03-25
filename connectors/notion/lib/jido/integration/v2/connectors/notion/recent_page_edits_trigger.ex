defmodule Jido.Integration.V2.Connectors.Notion.RecentPageEditsTrigger do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Connectors.Notion.ClientFactory
  alias Jido.Integration.V2.Connectors.Notion.ErrorMapper
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.RuntimeResult

  @capability_id "notion.pages.recently_edited"
  @event_type "connector.notion.pages.recently_edited.completed"
  @artifact_slug "pages_recently_edited"
  @default_page_size 10

  @spec run(map(), map()) :: {:ok, RuntimeResult.t()} | {:error, map(), RuntimeResult.t()}
  def run(input, context) when is_map(input) and is_map(context) do
    auth_binding = ClientFactory.auth_binding(context)
    checkpoint_cursor = checkpoint_cursor(input)
    params = search_params(input)

    case ClientFactory.build(context) do
      {:ok, client} ->
        case NotionSDK.Search.search(client, params) do
          {:ok, response} ->
            signals =
              response
              |> Map.get("results", [])
              |> Enum.map(&normalize_signal/1)
              |> Enum.filter(&newer_than_checkpoint?(&1, checkpoint_cursor))

            dedupe_keys = Enum.map(signals, &dedupe_key/1)
            next_cursor = next_checkpoint_cursor(signals, checkpoint_cursor)

            {:ok,
             RuntimeResult.new!(%{
               output: %{
                 capability_id: @capability_id,
                 auth_binding: auth_binding,
                 signals: signals,
                 checkpoint: %{
                   strategy: :timestamp_cursor,
                   cursor: next_cursor
                 },
                 dedupe_keys: dedupe_keys
               },
               events: [
                 %{
                   type: @event_type,
                   stream: :control,
                   payload: %{
                     capability_id: @capability_id,
                     auth_binding: auth_binding,
                     signal_count: length(signals),
                     checkpoint_cursor: next_cursor
                   }
                 }
               ],
               artifacts: [
                 ArtifactBuilder.build!(
                   run_id: context.run_id,
                   attempt_id: context.attempt_id,
                   artifact_type: :tool_output,
                   key: artifact_key(context),
                   content: %{
                     capability_id: @capability_id,
                     request: params,
                     signals: signals,
                     checkpoint: %{
                       strategy: :timestamp_cursor,
                       cursor: next_cursor
                     },
                     dedupe_keys: dedupe_keys,
                     auth_binding: auth_binding
                   },
                   metadata: %{
                     connector: "notion",
                     capability_id: @capability_id,
                     auth_binding: auth_binding,
                     signal_count: length(signals)
                   }
                 )
               ]
             })}

          {:error, %NotionSDK.Error{} = error} ->
            error_result(context, auth_binding, params, ErrorMapper.from_notion_error(error))
        end

      {:error, reason} ->
        error_result(context, auth_binding, params, ErrorMapper.from_reason(reason))
    end
  end

  defp error_result(context, auth_binding, params, mapped_error) do
    runtime_result =
      RuntimeResult.new!(%{
        output: %{
          capability_id: @capability_id,
          auth_binding: auth_binding,
          error: mapped_error
        },
        events: [
          %{
            type: "connector.notion.pages.recently_edited.failed",
            stream: :control,
            level: :warn,
            payload: %{
              capability_id: @capability_id,
              auth_binding: auth_binding,
              class: mapped_error.class,
              retryability: mapped_error.retryability
            }
          }
        ],
        artifacts: [
          ArtifactBuilder.build!(
            run_id: context.run_id,
            attempt_id: context.attempt_id,
            artifact_type: :tool_output,
            key: artifact_key(context, "_error"),
            content: %{
              capability_id: @capability_id,
              request: params,
              error: mapped_error,
              auth_binding: auth_binding
            },
            metadata: %{
              connector: "notion",
              capability_id: @capability_id,
              auth_binding: auth_binding
            }
          )
        ]
      })

    {:error, mapped_error, runtime_result}
  end

  defp search_params(input) do
    %{
      "filter" => %{
        "property" => "object",
        "value" => "page"
      },
      "sort" => %{
        "timestamp" => "last_edited_time",
        "direction" => "descending"
      },
      "page_size" => page_size(input)
    }
  end

  defp page_size(input) do
    case Contracts.get(input, :page_size) do
      value when is_integer(value) and value > 0 -> value
      _other -> @default_page_size
    end
  end

  defp checkpoint_cursor(input) do
    case Contracts.get(input, :checkpoint_cursor) do
      value when is_binary(value) ->
        if byte_size(String.trim(value)) > 0, do: value, else: nil

      _other ->
        nil
    end
  end

  defp normalize_signal(page) do
    %{
      page_id: Map.fetch!(page, "id"),
      last_edited_time: Map.fetch!(page, "last_edited_time"),
      title: extract_title(page),
      url: Map.fetch!(page, "url")
    }
  end

  defp extract_title(%{"properties" => properties}) when is_map(properties) do
    properties
    |> Map.get("Title", %{})
    |> Map.get("title", [])
    |> List.wrap()
    |> Enum.find_value("", fn segment ->
      Map.get(segment, "plain_text")
    end)
  end

  defp extract_title(_page), do: ""

  defp newer_than_checkpoint?(_signal, nil), do: true

  defp newer_than_checkpoint?(signal, checkpoint_cursor) do
    compare_iso8601(signal.last_edited_time, checkpoint_cursor) == :gt
  end

  defp next_checkpoint_cursor([], checkpoint_cursor), do: checkpoint_cursor

  defp next_checkpoint_cursor(signals, checkpoint_cursor) do
    newest_signal =
      Enum.max_by(signals, & &1.last_edited_time, fn -> nil end)

    case newest_signal do
      nil -> checkpoint_cursor
      %{last_edited_time: last_edited_time} -> last_edited_time
    end
  end

  defp dedupe_key(signal) do
    "#{signal.page_id}:#{signal.last_edited_time}"
  end

  defp compare_iso8601(left, right) do
    with {:ok, left_dt, _offset} <- DateTime.from_iso8601(left),
         {:ok, right_dt, _offset} <- DateTime.from_iso8601(right) do
      DateTime.compare(left_dt, right_dt)
    else
      _error ->
        left
        |> to_string()
        |> Kernel.>(to_string(right))
        |> if(do: :gt, else: :lt)
    end
  end

  defp artifact_key(context, suffix \\ "") do
    "notion/#{context.run_id}/#{context.attempt_id}/#{@artifact_slug}#{suffix}.term"
  end
end
