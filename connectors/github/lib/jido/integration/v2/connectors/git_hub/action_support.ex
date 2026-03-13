defmodule Jido.Integration.V2.Connectors.GitHub.ActionSupport do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Connectors.GitHub.Provider
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.RuntimeResult

  @connector_id "github"

  @type operation ::
          :issue_list
          | :issue_fetch
          | :issue_create
          | :issue_update
          | :issue_label
          | :issue_close
          | :comment_create
          | :comment_update

  @spec run(operation(), map(), map()) :: {:ok, RuntimeResult.t()} | {:error, term()}
  def run(operation, params, context) do
    auth_binding = auth_binding(context)

    with {:ok, provider_output} <- Provider.execute(operation, params, context) do
      output =
        provider_output
        |> Map.put(actor_field(operation), context.credential_lease.subject)
        |> Map.put(:auth_binding, auth_binding)

      artifact =
        ArtifactBuilder.build!(
          run_id: context.run_id,
          attempt_id: context.attempt_id,
          artifact_type: :tool_output,
          key: artifact_key(operation, context.run_id, context.attempt_id),
          content: %{
            operation: operation,
            request: params,
            response: output,
            auth_binding: auth_binding,
            execution_policy: context.policy_inputs.execution
          },
          metadata: %{
            connector: @connector_id,
            capability_id: context.capability.id,
            auth_binding: auth_binding
          }
        )

      {:ok,
       RuntimeResult.new!(%{
         output: output,
         events: [
           %{
             type: event_type(operation),
             stream: :control,
             payload: event_payload(operation, output, auth_binding)
           }
         ],
         artifacts: [artifact]
       })}
    end
  end

  defp auth_binding(context) do
    context.credential_lease.payload
    |> lease_value(:access_token)
    |> ArtifactBuilder.digest()
  end

  defp lease_value(payload, key) do
    case Contracts.get(payload, key) do
      nil -> raise ArgumentError, "missing credential lease field #{inspect(key)}"
      value -> value
    end
  end

  defp artifact_key(operation, run_id, attempt_id) do
    "github/#{run_id}/#{attempt_id}/#{artifact_slug(operation)}.term"
  end

  defp artifact_slug(:issue_list), do: "issue_list"
  defp artifact_slug(:issue_fetch), do: "issue_fetch"
  defp artifact_slug(:issue_create), do: "issue_create"
  defp artifact_slug(:issue_update), do: "issue_update"
  defp artifact_slug(:issue_label), do: "issue_label"
  defp artifact_slug(:issue_close), do: "issue_close"
  defp artifact_slug(:comment_create), do: "comment_create"
  defp artifact_slug(:comment_update), do: "comment_update"

  defp actor_field(:issue_list), do: :listed_by
  defp actor_field(:issue_fetch), do: :fetched_by
  defp actor_field(:issue_create), do: :opened_by
  defp actor_field(:issue_update), do: :updated_by
  defp actor_field(:issue_label), do: :labeled_by
  defp actor_field(:issue_close), do: :closed_by
  defp actor_field(:comment_create), do: :created_by
  defp actor_field(:comment_update), do: :updated_by

  defp event_type(:issue_list), do: "connector.github.issue.listed"
  defp event_type(:issue_fetch), do: "connector.github.issue.fetched"
  defp event_type(:issue_create), do: "connector.github.issue.created"
  defp event_type(:issue_update), do: "connector.github.issue.updated"
  defp event_type(:issue_label), do: "connector.github.issue.labeled"
  defp event_type(:issue_close), do: "connector.github.issue.closed"
  defp event_type(:comment_create), do: "connector.github.comment.created"
  defp event_type(:comment_update), do: "connector.github.comment.updated"

  defp event_payload(:issue_list, output, auth_binding) do
    %{
      repo: output.repo,
      total_count: output.total_count,
      page: output.page,
      auth_binding: auth_binding
    }
  end

  defp event_payload(:issue_fetch, output, auth_binding) do
    %{
      repo: output.repo,
      issue_number: output.issue_number,
      state: output.state,
      auth_binding: auth_binding
    }
  end

  defp event_payload(operation, output, auth_binding)
       when operation in [:issue_create, :issue_update, :issue_label, :issue_close] do
    base = %{repo: output.repo, issue_number: output.issue_number, auth_binding: auth_binding}

    case operation do
      :issue_create -> base
      :issue_update -> Map.put(base, :state, output.state)
      :issue_label -> Map.put(base, :label_count, length(output.labels))
      :issue_close -> Map.put(base, :state, output.state)
    end
  end

  defp event_payload(:comment_create, output, auth_binding) do
    %{
      repo: output.repo,
      issue_number: output.issue_number,
      comment_id: output.comment_id,
      auth_binding: auth_binding
    }
  end

  defp event_payload(:comment_update, output, auth_binding) do
    %{
      repo: output.repo,
      comment_id: output.comment_id,
      auth_binding: auth_binding
    }
  end
end
