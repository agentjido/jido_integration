defmodule Jido.Integration.V2.Connectors.GitHub.Operation do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Connectors.GitHub.ClientFactory
  alias Jido.Integration.V2.Connectors.GitHub.ErrorMapper
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.RuntimeResult

  @repo_regex ~r/\A[^\/\s]+\/[^\/\s]+\z/

  @spec run(map(), map()) :: {:ok, RuntimeResult.t()} | {:error, map(), RuntimeResult.t()}
  def run(input, context) when is_map(input) and is_map(context) do
    metadata = Map.fetch!(context.capability, :metadata)
    auth_binding = ClientFactory.auth_binding(context)

    with {:ok, client} <- ClientFactory.build(context),
         {:ok, sdk_params} <- sdk_params(metadata.operation, input),
         {:ok, response} <- invoke(metadata, client, sdk_params) do
      output = normalize_output(metadata.operation, response, input, context, auth_binding)

      {:ok,
       RuntimeResult.new!(%{
         output: output,
         events: [
           %{
             type: metadata.event_type,
             stream: :control,
             payload: event_payload(metadata.operation, output, auth_binding)
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
               request: Redaction.redact(input),
               response: output,
               auth_binding: auth_binding,
               execution_policy: context.policy_inputs.execution
             },
             metadata: %{
               connector: "github",
               capability_id: context.capability.id,
               auth_binding: auth_binding
             }
           )
         ]
       })}
    else
      {:error, %GitHubEx.Error{} = error} ->
        error_result(context, metadata, input, auth_binding, ErrorMapper.from_github_error(error))

      {:error, reason} ->
        error_result(context, metadata, input, auth_binding, ErrorMapper.from_reason(reason))
    end
  rescue
    error ->
      metadata = Map.fetch!(context.capability, :metadata)
      auth_binding = ClientFactory.auth_binding(context)
      error_result(context, metadata, input, auth_binding, ErrorMapper.from_reason(error))
  end

  defp invoke(metadata, client, sdk_params) do
    apply(metadata.sdk_module, metadata.sdk_function, [client, sdk_params])
  end

  defp sdk_params(:issue_list, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_optional_positive_integer(input, :per_page),
         :ok <- validate_optional_positive_integer(input, :page) do
      {:ok,
       Map.merge(repo_params, take_present(input, [:state, :per_page, :page, :request_opts]))}
    end
  end

  defp sdk_params(:issue_fetch, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :issue_number) do
      {:ok, Map.merge(repo_params, take_present(input, [:issue_number, :request_opts]))}
    end
  end

  defp sdk_params(:issue_create, input) do
    with {:ok, repo_params} <- repo_params(input) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [:title, :body, :labels, :assignees, :request_opts])
       )}
    end
  end

  defp sdk_params(:issue_update, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :issue_number) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [
           :issue_number,
           :title,
           :body,
           :state,
           :labels,
           :assignees,
           :request_opts
         ])
       )}
    end
  end

  defp sdk_params(:issue_label, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :issue_number) do
      {:ok, Map.merge(repo_params, take_present(input, [:issue_number, :labels, :request_opts]))}
    end
  end

  defp sdk_params(:issue_close, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :issue_number) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [:issue_number, :request_opts])
         |> Map.put(:state, "closed")
       )}
    end
  end

  defp sdk_params(:comment_create, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :issue_number) do
      {:ok, Map.merge(repo_params, take_present(input, [:issue_number, :body, :request_opts]))}
    end
  end

  defp sdk_params(:comment_update, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :comment_id) do
      {:ok, Map.merge(repo_params, take_present(input, [:comment_id, :body, :request_opts]))}
    end
  end

  defp normalize_output(:issue_list, response, input, context, auth_binding)
       when is_list(response) do
    %{
      repo: repo_value(input),
      state: Map.get(input, :state, "open"),
      page: Map.get(input, :page, 1),
      per_page: Map.get(input, :per_page, 30),
      total_count: length(response),
      issues:
        Enum.map(response, fn issue ->
          %{
            repo: repo_value(input),
            issue_number: Map.get(issue, "number"),
            title: Map.get(issue, "title"),
            state: Map.get(issue, "state"),
            labels: normalize_labels(Map.get(issue, "labels", []))
          }
        end),
      listed_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:issue_fetch, response, input, context, auth_binding) do
    %{
      repo: repo_value(input),
      issue_number: Map.get(response, "number", Map.get(input, :issue_number)),
      title: Map.get(response, "title"),
      body: Map.get(response, "body"),
      state: Map.get(response, "state"),
      labels: normalize_labels(Map.get(response, "labels", [])),
      fetched_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:issue_create, response, input, context, auth_binding) do
    %{
      repo: repo_value(input),
      issue_number: Map.get(response, "number"),
      title: Map.get(response, "title", Map.get(input, :title)),
      body: Map.get(response, "body", Map.get(input, :body)),
      state: Map.get(response, "state", "open"),
      labels: normalize_labels(Map.get(response, "labels", Map.get(input, :labels, []))),
      assignees: normalize_logins(Map.get(response, "assignees", Map.get(input, :assignees, []))),
      opened_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:issue_update, response, input, context, auth_binding) do
    %{
      repo: repo_value(input),
      issue_number: Map.get(response, "number", Map.get(input, :issue_number)),
      title: Map.get(response, "title", Map.get(input, :title)),
      body: Map.get(response, "body", Map.get(input, :body)),
      state: Map.get(response, "state", Map.get(input, :state, "open")),
      labels: normalize_labels(Map.get(response, "labels", Map.get(input, :labels, []))),
      assignees: normalize_logins(Map.get(response, "assignees", Map.get(input, :assignees, []))),
      updated_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:issue_label, response, input, context, auth_binding)
       when is_list(response) do
    %{
      repo: repo_value(input),
      issue_number: Map.get(input, :issue_number),
      labels: normalize_labels(response),
      labeled_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:issue_close, response, input, context, auth_binding) do
    %{
      repo: repo_value(input),
      issue_number: Map.get(response, "number", Map.get(input, :issue_number)),
      state: Map.get(response, "state", "closed"),
      closed_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:comment_create, response, input, context, auth_binding) do
    %{
      repo: repo_value(input),
      issue_number: Map.get(input, :issue_number),
      comment_id: Map.get(response, "id"),
      body: Map.get(response, "body", Map.get(input, :body)),
      created_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:comment_update, response, input, context, auth_binding) do
    %{
      repo: repo_value(input),
      comment_id: Map.get(response, "id", Map.get(input, :comment_id)),
      body: Map.get(response, "body", Map.get(input, :body)),
      updated_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp error_result(context, metadata, input, auth_binding, mapped_error) do
    runtime_result =
      RuntimeResult.new!(%{
        output: %{
          capability_id: context.capability.id,
          auth_binding: auth_binding,
          error: mapped_error
        },
        events: [
          %{
            type: metadata.failure_event_type,
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
              request: Redaction.redact(input),
              error: mapped_error,
              auth_binding: auth_binding
            },
            metadata: %{
              connector: "github",
              capability_id: context.capability.id,
              auth_binding: auth_binding
            }
          )
        ]
      })

    {:error, mapped_error, runtime_result}
  end

  defp artifact_key(context, slug) do
    "github/#{context.run_id}/#{context.attempt_id}/#{slug}.term"
  end

  defp repo_params(input) do
    case repo_value(input) do
      repo when is_binary(repo) ->
        if repo =~ @repo_regex do
          [owner, repo_name] = String.split(repo, "/", parts: 2)
          {:ok, %{owner: owner, repo: repo_name}}
        else
          {:error, {:invalid_repo, repo}}
        end

      other ->
        {:error, {:invalid_repo, other}}
    end
  end

  defp repo_value(input) do
    Map.get(input, :repo) || Map.get(input, "repo")
  end

  defp take_present(input, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case fetch_input(input, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp fetch_input(input, key) do
    cond do
      Map.has_key?(input, key) ->
        {:ok, Map.fetch!(input, key)}

      Map.has_key?(input, to_string(key)) ->
        {:ok, Map.fetch!(input, to_string(key))}

      true ->
        :error
    end
  end

  defp validate_required_positive_integer(input, field) do
    case fetch_input(input, field) do
      {:ok, value} ->
        validate_positive_integer(field, value)

      :error ->
        {:error, {:invalid_input, field, nil}}
    end
  end

  defp validate_optional_positive_integer(input, field) do
    case fetch_input(input, field) do
      {:ok, value} -> validate_positive_integer(field, value)
      :error -> :ok
    end
  end

  defp validate_positive_integer(_field, value) when is_integer(value) and value > 0, do: :ok

  defp validate_positive_integer(field, value) do
    {:error, {:invalid_input, field, value}}
  end

  defp normalize_labels(labels) when is_list(labels) do
    Enum.map(labels, fn
      %{"name" => name} -> name
      label when is_binary(label) -> label
      other -> inspect(other)
    end)
  end

  defp normalize_labels(_labels), do: []

  defp normalize_logins(logins) when is_list(logins) do
    Enum.map(logins, fn
      %{"login" => login} -> login
      login when is_binary(login) -> login
      other -> inspect(other)
    end)
  end

  defp normalize_logins(_logins), do: []

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
