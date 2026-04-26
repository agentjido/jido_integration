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

  defp sdk_params(:check_runs_list_for_ref, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_non_empty_string(input, :ref),
         :ok <- validate_optional_positive_integer(input, :app_id),
         :ok <- validate_optional_positive_integer(input, :per_page),
         :ok <- validate_optional_positive_integer(input, :page) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [
           :ref,
           :check_name,
           :status,
           :filter,
           :app_id,
           :per_page,
           :page,
           :request_opts
         ])
       )}
    end
  end

  defp sdk_params(:commit_statuses_get_combined, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_non_empty_string(input, :ref),
         :ok <- validate_optional_positive_integer(input, :per_page),
         :ok <- validate_optional_positive_integer(input, :page) do
      {:ok, Map.merge(repo_params, take_present(input, [:ref, :per_page, :page, :request_opts]))}
    end
  end

  defp sdk_params(:commit_statuses_list, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_non_empty_string(input, :ref),
         :ok <- validate_optional_positive_integer(input, :per_page),
         :ok <- validate_optional_positive_integer(input, :page) do
      {:ok, Map.merge(repo_params, take_present(input, [:ref, :per_page, :page, :request_opts]))}
    end
  end

  defp sdk_params(:commits_list, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_optional_positive_integer(input, :per_page),
         :ok <- validate_optional_positive_integer(input, :page) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [
           :sha,
           :path,
           :author,
           :committer,
           :since,
           :until,
           :per_page,
           :page,
           :request_opts
         ])
       )}
    end
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

  defp sdk_params(:pr_create, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_non_empty_string(input, :title),
         :ok <- validate_required_non_empty_string(input, :head),
         :ok <- validate_required_non_empty_string(input, :base) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [
           :title,
           :body,
           :head,
           :base,
           :draft,
           :maintainer_can_modify,
           :request_opts
         ])
       )}
    end
  end

  defp sdk_params(:pr_fetch, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :pull_number) do
      {:ok, Map.merge(repo_params, take_present(input, [:pull_number, :request_opts]))}
    end
  end

  defp sdk_params(:pr_list, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_optional_positive_integer(input, :per_page),
         :ok <- validate_optional_positive_integer(input, :page) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [
           :state,
           :head,
           :base,
           :sort,
           :direction,
           :per_page,
           :page,
           :request_opts
         ])
       )}
    end
  end

  defp sdk_params(:pr_update, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :pull_number) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [
           :pull_number,
           :title,
           :body,
           :state,
           :base,
           :maintainer_can_modify,
           :request_opts
         ])
       )}
    end
  end

  defp sdk_params(:pr_reviews_list, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :pull_number),
         :ok <- validate_optional_positive_integer(input, :per_page),
         :ok <- validate_optional_positive_integer(input, :page) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [:pull_number, :per_page, :page, :request_opts])
       )}
    end
  end

  defp sdk_params(:pr_review_comments_list, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :pull_number),
         :ok <- validate_optional_positive_integer(input, :per_page),
         :ok <- validate_optional_positive_integer(input, :page) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [
           :pull_number,
           :sort,
           :direction,
           :since,
           :per_page,
           :page,
           :request_opts
         ])
       )}
    end
  end

  defp sdk_params(:pr_review_create, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :pull_number) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [:pull_number, :body, :event, :comments, :commit_id, :request_opts])
       )}
    end
  end

  defp sdk_params(:pr_review_comment_create, input) do
    with {:ok, repo_params} <- repo_params(input),
         :ok <- validate_required_positive_integer(input, :pull_number),
         :ok <- validate_required_non_empty_string(input, :body),
         :ok <- validate_required_non_empty_string(input, :commit_id),
         :ok <- validate_required_non_empty_string(input, :path),
         :ok <- validate_optional_positive_integer(input, :position),
         :ok <- validate_optional_positive_integer(input, :line),
         :ok <- validate_optional_positive_integer(input, :start_line) do
      {:ok,
       Map.merge(
         repo_params,
         take_present(input, [
           :pull_number,
           :body,
           :commit_id,
           :path,
           :position,
           :line,
           :side,
           :start_line,
           :start_side,
           :request_opts
         ])
       )}
    end
  end

  defp normalize_output(:check_runs_list_for_ref, response, input, context, auth_binding) do
    check_runs =
      response
      |> Map.get("check_runs", [])
      |> Enum.map(&normalize_check_run/1)

    %{
      repo: repo_value(input),
      ref: input_value(input, :ref),
      total_count: Map.get(response, "total_count", length(check_runs)),
      check_runs: check_runs,
      listed_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:commit_statuses_get_combined, response, input, context, auth_binding) do
    statuses =
      response
      |> Map.get("statuses", [])
      |> Enum.map(&normalize_commit_status/1)

    %{
      repo: repo_value(input),
      ref: input_value(input, :ref),
      sha: Map.get(response, "sha", input_value(input, :ref)),
      state: Map.get(response, "state"),
      total_count: Map.get(response, "total_count", length(statuses)),
      statuses: statuses,
      fetched_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:commit_statuses_list, response, input, context, auth_binding)
       when is_list(response) do
    statuses = Enum.map(response, &normalize_commit_status/1)

    %{
      repo: repo_value(input),
      ref: input_value(input, :ref),
      total_count: length(statuses),
      statuses: statuses,
      listed_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:commits_list, response, input, context, auth_binding)
       when is_list(response) do
    commits = Enum.map(response, &normalize_commit/1)

    %{
      repo: repo_value(input),
      sha: input_value(input, :sha),
      path: input_value(input, :path),
      page: input_value(input, :page, 1),
      per_page: input_value(input, :per_page, 30),
      total_count: length(commits),
      commits: commits,
      listed_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
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

  defp normalize_output(:pr_create, response, _input, context, auth_binding) do
    response
    |> normalize_pull_request()
    |> Map.merge(%{opened_by: context.credential_lease.subject, auth_binding: auth_binding})
  end

  defp normalize_output(:pr_fetch, response, _input, context, auth_binding) do
    response
    |> normalize_pull_request()
    |> Map.merge(%{fetched_by: context.credential_lease.subject, auth_binding: auth_binding})
  end

  defp normalize_output(:pr_list, response, input, context, auth_binding)
       when is_list(response) do
    pull_requests = Enum.map(response, &normalize_pull_request/1)

    %{
      repo: repo_value(input),
      state: input_value(input, :state, "open"),
      page: input_value(input, :page, 1),
      per_page: input_value(input, :per_page, 30),
      total_count: length(pull_requests),
      pull_requests: pull_requests,
      listed_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:pr_update, response, _input, context, auth_binding) do
    response
    |> normalize_pull_request()
    |> Map.merge(%{updated_by: context.credential_lease.subject, auth_binding: auth_binding})
  end

  defp normalize_output(:pr_reviews_list, response, input, context, auth_binding)
       when is_list(response) do
    reviews = Enum.map(response, &normalize_review/1)

    %{
      repo: repo_value(input),
      pull_number: input_value(input, :pull_number),
      total_count: length(reviews),
      reviews: reviews,
      listed_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:pr_review_comments_list, response, input, context, auth_binding)
       when is_list(response) do
    comments = Enum.map(response, &normalize_review_comment/1)

    %{
      repo: repo_value(input),
      pull_number: input_value(input, :pull_number),
      total_count: length(comments),
      comments: comments,
      listed_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:pr_review_create, response, input, context, auth_binding) do
    %{
      repo: repo_value(input),
      pull_number: input_value(input, :pull_number),
      review: normalize_review(response),
      created_by: context.credential_lease.subject,
      auth_binding: auth_binding
    }
  end

  defp normalize_output(:pr_review_comment_create, response, input, context, auth_binding) do
    %{
      repo: repo_value(input),
      pull_number: input_value(input, :pull_number),
      comment: normalize_review_comment(response),
      created_by: context.credential_lease.subject,
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

  defp input_value(input, key, default \\ nil) do
    case fetch_input(input, key) do
      {:ok, value} -> value
      :error -> default
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

  defp validate_required_non_empty_string(input, field) do
    case fetch_input(input, field) do
      {:ok, value} when is_binary(value) and value != "" ->
        :ok

      {:ok, value} ->
        {:error, {:invalid_input, field, value}}

      :error ->
        {:error, {:invalid_input, field, nil}}
    end
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

  defp normalize_pull_request(response) do
    %{
      repo: pull_request_repo(response),
      pull_number: Map.get(response, "number"),
      title: Map.get(response, "title"),
      body: Map.get(response, "body"),
      state: Map.get(response, "state"),
      draft: Map.get(response, "draft", false),
      merged: Map.get(response, "merged", false),
      mergeable: Map.get(response, "mergeable"),
      maintainer_can_modify: Map.get(response, "maintainer_can_modify", false),
      html_url: Map.get(response, "html_url"),
      diff_url: Map.get(response, "diff_url"),
      patch_url: Map.get(response, "patch_url"),
      commits_url: Map.get(response, "commits_url"),
      review_comments_url: Map.get(response, "review_comments_url"),
      head: normalize_ref(Map.get(response, "head")),
      base: normalize_ref(Map.get(response, "base")),
      user: login(Map.get(response, "user")),
      labels: normalize_labels(Map.get(response, "labels", [])),
      requested_reviewers: normalize_logins(Map.get(response, "requested_reviewers", []))
    }
  end

  defp pull_request_repo(response) do
    get_in(response, ["head", "repo", "full_name"]) ||
      get_in(response, ["base", "repo", "full_name"])
  end

  defp normalize_ref(%{} = ref) do
    %{
      ref: Map.get(ref, "ref"),
      sha: Map.get(ref, "sha"),
      repo: get_in(ref, ["repo", "full_name"])
    }
  end

  defp normalize_ref(_ref), do: %{ref: nil, sha: nil, repo: nil}

  defp normalize_review(review) do
    %{
      review_id: Map.get(review, "id"),
      state: Map.get(review, "state"),
      body: Map.get(review, "body"),
      commit_id: Map.get(review, "commit_id"),
      submitted_at: Map.get(review, "submitted_at"),
      user: login(Map.get(review, "user")),
      html_url: Map.get(review, "html_url")
    }
  end

  defp normalize_review_comment(comment) do
    %{
      comment_id: Map.get(comment, "id"),
      body: Map.get(comment, "body"),
      path: Map.get(comment, "path"),
      diff_hunk: Map.get(comment, "diff_hunk"),
      position: Map.get(comment, "position"),
      line: Map.get(comment, "line"),
      side: Map.get(comment, "side"),
      start_line: Map.get(comment, "start_line"),
      start_side: Map.get(comment, "start_side"),
      commit_id: Map.get(comment, "commit_id"),
      original_commit_id: Map.get(comment, "original_commit_id"),
      in_reply_to_id: Map.get(comment, "in_reply_to_id"),
      pull_request_review_id: Map.get(comment, "pull_request_review_id"),
      user: login(Map.get(comment, "user")),
      html_url: Map.get(comment, "html_url")
    }
  end

  defp normalize_commit_status(status) do
    %{
      status_id: Map.get(status, "id"),
      state: Map.get(status, "state"),
      context: Map.get(status, "context"),
      description: Map.get(status, "description"),
      target_url: Map.get(status, "target_url"),
      created_at: Map.get(status, "created_at"),
      updated_at: Map.get(status, "updated_at")
    }
  end

  defp normalize_check_run(check_run) do
    %{
      check_run_id: Map.get(check_run, "id"),
      name: Map.get(check_run, "name"),
      head_sha: Map.get(check_run, "head_sha"),
      status: Map.get(check_run, "status"),
      conclusion: Map.get(check_run, "conclusion"),
      html_url: Map.get(check_run, "html_url"),
      details_url: Map.get(check_run, "details_url"),
      started_at: Map.get(check_run, "started_at"),
      completed_at: Map.get(check_run, "completed_at"),
      app_slug: get_in(check_run, ["app", "slug"])
    }
  end

  defp normalize_commit(commit) do
    commit_body = Map.get(commit, "commit", %{})
    author = Map.get(commit_body, "author", %{})
    committer = Map.get(commit_body, "committer", %{})

    %{
      sha: Map.get(commit, "sha"),
      html_url: Map.get(commit, "html_url"),
      message: Map.get(commit_body, "message"),
      author_name: Map.get(author, "name"),
      author_email: Map.get(author, "email"),
      author_date: Map.get(author, "date"),
      committer_name: Map.get(committer, "name"),
      committer_email: Map.get(committer, "email"),
      committer_date: Map.get(committer, "date")
    }
  end

  defp login(%{"login" => login}), do: login
  defp login(_user), do: nil

  defp event_payload(:check_runs_list_for_ref, output, auth_binding) do
    %{
      repo: output.repo,
      ref: output.ref,
      total_count: output.total_count,
      auth_binding: auth_binding
    }
  end

  defp event_payload(:commit_statuses_get_combined, output, auth_binding) do
    %{
      repo: output.repo,
      ref: output.ref,
      state: output.state,
      total_count: output.total_count,
      auth_binding: auth_binding
    }
  end

  defp event_payload(:commit_statuses_list, output, auth_binding) do
    %{
      repo: output.repo,
      ref: output.ref,
      total_count: output.total_count,
      auth_binding: auth_binding
    }
  end

  defp event_payload(:commits_list, output, auth_binding) do
    %{
      repo: output.repo,
      total_count: output.total_count,
      auth_binding: auth_binding
    }
  end

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

  defp event_payload(operation, output, auth_binding)
       when operation in [:pr_create, :pr_fetch, :pr_update] do
    %{
      repo: output.repo,
      pull_number: output.pull_number,
      state: output.state,
      auth_binding: auth_binding
    }
  end

  defp event_payload(:pr_list, output, auth_binding) do
    %{
      repo: output.repo,
      total_count: output.total_count,
      page: output.page,
      auth_binding: auth_binding
    }
  end

  defp event_payload(:pr_reviews_list, output, auth_binding) do
    %{
      repo: output.repo,
      pull_number: output.pull_number,
      total_count: output.total_count,
      auth_binding: auth_binding
    }
  end

  defp event_payload(:pr_review_comments_list, output, auth_binding) do
    %{
      repo: output.repo,
      pull_number: output.pull_number,
      total_count: output.total_count,
      auth_binding: auth_binding
    }
  end

  defp event_payload(:pr_review_create, output, auth_binding) do
    %{
      repo: output.repo,
      pull_number: output.pull_number,
      review_id: output.review.review_id,
      auth_binding: auth_binding
    }
  end

  defp event_payload(:pr_review_comment_create, output, auth_binding) do
    %{
      repo: output.repo,
      pull_number: output.pull_number,
      comment_id: output.comment.comment_id,
      auth_binding: auth_binding
    }
  end
end
