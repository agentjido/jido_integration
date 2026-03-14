defmodule Jido.Integration.V2.Connectors.Notion.Operation do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Connectors.Notion.ClientFactory
  alias Jido.Integration.V2.Connectors.Notion.ErrorMapper
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.RuntimeResult

  @spec run(map(), map()) :: {:ok, RuntimeResult.t()} | {:error, map(), RuntimeResult.t()}
  def run(input, context) when is_map(input) and is_map(context) do
    metadata = Map.fetch!(context.capability, :metadata)
    params = stringify_keys(input)
    auth_binding = ClientFactory.auth_binding(context)

    with {:ok, client} <- ClientFactory.build(context),
         {:ok, response} <- invoke(metadata, client, params) do
      output = %{
        capability_id: context.capability.id,
        auth_binding: auth_binding,
        data: response
      }

      {:ok,
       RuntimeResult.new!(%{
         output: output,
         events: [
           %{
             type: "connector.notion.#{metadata.event_suffix}.completed",
             stream: :control,
             payload: %{
               capability_id: context.capability.id,
               auth_binding: auth_binding
             }
           }
         ],
         artifacts: [
           ArtifactBuilder.build!(
             run_id: context.run_id,
             attempt_id: context.attempt_id,
             artifact_type: :tool_output,
             key: artifact_key(context, metadata.artifact_slug),
             content: %{
               capability_id: context.capability.id,
               request: Redaction.redact(params),
               response: response,
               auth_binding: auth_binding
             },
             metadata: %{
               connector: "notion",
               capability_id: context.capability.id,
               auth_binding: auth_binding
             }
           )
         ]
       })}
    else
      {:error, %NotionSDK.Error{} = error} ->
        error_result(
          context,
          metadata,
          params,
          auth_binding,
          ErrorMapper.from_notion_error(error)
        )

      {:error, %Pristine.Error{} = error} ->
        error_result(
          context,
          metadata,
          params,
          auth_binding,
          ErrorMapper.from_pristine_error(error)
        )

      {:error, reason} ->
        error_result(context, metadata, params, auth_binding, ErrorMapper.from_reason(reason))
    end
  rescue
    error ->
      metadata = Map.fetch!(context.capability, :metadata)
      params = stringify_keys(input)
      auth_binding = ClientFactory.auth_binding(context)
      error_result(context, metadata, params, auth_binding, ErrorMapper.from_reason(error))
  end

  defp invoke(metadata, client, params) do
    apply(metadata.sdk_module, metadata.sdk_function, [client, params])
  end

  defp error_result(context, metadata, params, auth_binding, mapped_error) do
    runtime_result =
      RuntimeResult.new!(%{
        output: %{
          capability_id: context.capability.id,
          auth_binding: auth_binding,
          error: mapped_error
        },
        events: [
          %{
            type: "connector.notion.#{metadata.event_suffix}.failed",
            stream: :control,
            level: :warn,
            payload: %{
              capability_id: context.capability.id,
              class: mapped_error.class,
              retryability: mapped_error.retryability,
              auth_binding: auth_binding
            }
          }
        ],
        artifacts: [
          ArtifactBuilder.build!(
            run_id: context.run_id,
            attempt_id: context.attempt_id,
            artifact_type: :tool_output,
            key: artifact_key(context, metadata.artifact_slug <> "_error"),
            content: %{
              capability_id: context.capability.id,
              request: Redaction.redact(params),
              error: mapped_error,
              auth_binding: auth_binding
            },
            metadata: %{
              connector: "notion",
              capability_id: context.capability.id,
              auth_binding: auth_binding
            }
          )
        ]
      })

    {:error, mapped_error, runtime_result}
  end

  defp artifact_key(context, slug) do
    "notion/#{context.run_id}/#{context.attempt_id}/#{slug}.term"
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
