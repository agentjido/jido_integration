defmodule Jido.Integration.V2.Connectors.Notion.Operation do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Connectors.Notion.ClientFactory
  alias Jido.Integration.V2.Connectors.Notion.ErrorMapper
  alias Jido.Integration.V2.Connectors.Notion.SchemaContext
  alias Jido.Integration.V2.Connectors.Notion.SchemaResolver
  alias Jido.Integration.V2.Connectors.Notion.SchemaValidator
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.RuntimeResult

  @spec run(map(), map()) :: {:ok, RuntimeResult.t()} | {:error, map(), RuntimeResult.t()}
  def run(input, context) when is_map(input) and is_map(context) do
    metadata = Map.fetch!(context.capability, :metadata)
    params = stringify_keys(input)
    auth_binding = ClientFactory.auth_binding(context)

    case ClientFactory.build(context) do
      {:ok, client} ->
        case execute_with_schema(context.capability.id, metadata, client, params) do
          {:ok, response, schema_context} ->
            {:ok,
             success_result(context, metadata, params, auth_binding, response, schema_context)}

          {:error, %NotionSDK.Error{} = error, schema_context} ->
            error_result(
              context,
              metadata,
              params,
              auth_binding,
              ErrorMapper.from_notion_error(error),
              schema_context
            )

          {:error, %Pristine.Error{} = error, schema_context} ->
            error_result(
              context,
              metadata,
              params,
              auth_binding,
              ErrorMapper.from_pristine_error(error),
              schema_context
            )

          {:error, %{code: _code} = mapped_error, schema_context} ->
            error_result(context, metadata, params, auth_binding, mapped_error, schema_context)

          {:error, reason, schema_context} ->
            error_result(
              context,
              metadata,
              params,
              auth_binding,
              ErrorMapper.from_reason(reason),
              schema_context
            )
        end

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

  defp execute_with_schema(capability_id, metadata, client, params) do
    case SchemaResolver.resolve_for_input(metadata, client, params) do
      {:ok, input_schema_context} ->
        execute_with_resolved_input_schema(
          capability_id,
          metadata,
          client,
          params,
          input_schema_context
        )

      {:error, reason} ->
        {:error, reason, nil}
    end
  end

  defp execute_with_resolved_input_schema(
         capability_id,
         metadata,
         client,
         params,
         input_schema_context
       ) do
    with :ok <-
           SchemaValidator.validate_input(capability_id, metadata, params, input_schema_context),
         {:ok, response} <- invoke(metadata, client, params),
         {:ok, schema_context} <-
           resolve_output_schema_context(metadata, client, params, response, input_schema_context) do
      {:ok, response, schema_context}
    else
      {:error, reason} ->
        {:error, reason, input_schema_context}
    end
  end

  defp resolve_output_schema_context(metadata, client, params, response, input_schema_context) do
    case SchemaResolver.resolve_for_output(
           metadata,
           client,
           params,
           response,
           input_schema_context
         ) do
      {:ok, nil} -> {:ok, input_schema_context}
      {:ok, output_schema_context} -> {:ok, output_schema_context}
      {:error, reason} -> {:error, reason}
    end
  end

  defp invoke(metadata, client, params) do
    apply(metadata.sdk_module, metadata.sdk_function, [client, params])
  end

  defp success_result(context, metadata, params, auth_binding, response, schema_context) do
    schema_context_summary = SchemaContext.summary(schema_context)

    RuntimeResult.new!(%{
      output: %{
        capability_id: context.capability.id,
        auth_binding: auth_binding,
        data: response
      },
      events: [
        %{
          type: "connector.notion.#{metadata.event_suffix}.completed",
          stream: :control,
          payload:
            success_payload(
              context.capability.id,
              auth_binding,
              schema_context_summary
            )
        }
      ],
      artifacts: [
        ArtifactBuilder.build!(
          run_id: context.run_id,
          attempt_id: context.attempt_id,
          artifact_type: :tool_output,
          key: artifact_key(context, metadata.artifact_slug),
          content:
            success_artifact_content(
              context.capability.id,
              params,
              response,
              auth_binding,
              schema_context_summary
            ),
          metadata:
            artifact_metadata(
              context.capability.id,
              auth_binding,
              schema_context_summary
            )
        )
      ]
    })
  end

  defp error_result(context, metadata, params, auth_binding, mapped_error, schema_context \\ nil) do
    schema_context_summary = SchemaContext.summary(schema_context)

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
            payload:
              failure_payload(
                context.capability.id,
                mapped_error,
                auth_binding,
                schema_context_summary
              )
          }
        ],
        artifacts: [
          ArtifactBuilder.build!(
            run_id: context.run_id,
            attempt_id: context.attempt_id,
            artifact_type: :tool_output,
            key: artifact_key(context, metadata.artifact_slug <> "_error"),
            content:
              failure_artifact_content(
                context.capability.id,
                params,
                mapped_error,
                auth_binding,
                schema_context_summary
              ),
            metadata:
              artifact_metadata(
                context.capability.id,
                auth_binding,
                schema_context_summary
              )
          )
        ]
      })

    {:error, mapped_error, runtime_result}
  end

  defp artifact_key(context, slug) do
    "notion/#{context.run_id}/#{context.attempt_id}/#{slug}.term"
  end

  defp success_payload(capability_id, auth_binding, schema_context_summary) do
    %{
      capability_id: capability_id,
      auth_binding: auth_binding
    }
    |> maybe_put(:schema_context, schema_context_summary)
  end

  defp failure_payload(capability_id, mapped_error, auth_binding, schema_context_summary) do
    %{
      capability_id: capability_id,
      class: mapped_error.class,
      retryability: mapped_error.retryability,
      auth_binding: auth_binding
    }
    |> maybe_put(:schema_context, schema_context_summary)
  end

  defp success_artifact_content(
         capability_id,
         params,
         response,
         auth_binding,
         schema_context_summary
       ) do
    %{
      capability_id: capability_id,
      request: Redaction.redact(params),
      response: response,
      auth_binding: auth_binding
    }
    |> maybe_put(:schema_context, schema_context_summary)
  end

  defp failure_artifact_content(
         capability_id,
         params,
         mapped_error,
         auth_binding,
         schema_context_summary
       ) do
    %{
      capability_id: capability_id,
      request: Redaction.redact(params),
      error: mapped_error,
      auth_binding: auth_binding
    }
    |> maybe_put(:schema_context, schema_context_summary)
  end

  defp artifact_metadata(capability_id, auth_binding, schema_context_summary) do
    %{
      connector: "notion",
      capability_id: capability_id,
      auth_binding: auth_binding
    }
    |> maybe_put(:schema_context, schema_context_summary)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
