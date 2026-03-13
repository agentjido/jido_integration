defmodule Jido.Integration.Connectors.GitHub do
  @moduledoc """
  GitHub connector — the first first-party reference connector package.

  Provides read/write access to GitHub issues and comments, plus
  webhook triggers for push, PR, and issue events.

  ## Operations

  - `github.list_issues` — list issues with filters
  - `github.fetch_issue` — fetch a single issue
  - `github.create_issue` — create a new issue
  - `github.update_issue` — update title/body/state
  - `github.label_issue` — add labels to an issue
  - `github.close_issue` — close an issue
  - `github.create_comment` — add a comment to an issue/PR
  - `github.update_comment` — update an existing comment

  ## Triggers

  - `github.webhook.push` — push/PR/issue webhook events

  ## Auth

  Uses OAuth2 with GitHub's authorization code flow. Requires
  `repo` scope for full issue access, `public_repo` for public repos only.

  ## Configuration

  The adapter requires an HTTP client to be provided via the `:http_client`
  option. In production this would be `Req`, in tests a mock.

      config :jido_integration_github, Jido.Integration.Connectors.GitHub,
        http_client: Jido.Integration.Connectors.GitHub.DefaultClient
  """

  @behaviour Jido.Integration.Adapter

  alias Jido.Integration.{Error, Manifest}

  @github_api_base "https://api.github.com"
  @manifest_path Path.expand(
                   "../../../../priv/jido/integration/connectors/github/manifest.json",
                   __DIR__
                 )
  @external_resource @manifest_path

  @impl true
  def id, do: "github"

  @impl true
  def manifest do
    @manifest_path
    |> File.read!()
    |> Jason.decode!()
    |> Manifest.new!()
  end

  @impl true
  def validate_config(config) do
    required = ["owner", "repo"]
    missing = Enum.filter(required, &(not Map.has_key?(config, &1)))

    if missing == [] do
      {:ok, config}
    else
      {:error, Error.new(:invalid_request, "Missing config: #{Enum.join(missing, ", ")}")}
    end
  end

  @impl true
  def health(opts) do
    case http_client(opts).get("#{@github_api_base}/rate_limit", headers(opts)) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{status: :healthy, details: %{"rate_limit" => body}}}

      {:ok, %{status: 401}} ->
        {:ok, %{status: :degraded, details: %{"reason" => "auth_failed"}}}

      {:error, reason} ->
        {:error, Error.new(:unavailable, "GitHub API unreachable: #{inspect(reason)}")}
    end
  end

  @impl true
  def run("github.list_issues", args, opts) do
    with :ok <- require_args(args, ["owner", "repo"]) do
      owner = args["owner"]
      repo = args["repo"]
      state = Map.get(args, "state", "open")
      per_page = Map.get(args, "per_page", 30)
      page = Map.get(args, "page", 1)

      url =
        "#{@github_api_base}/repos/#{owner}/#{repo}/issues?state=#{state}&per_page=#{per_page}&page=#{page}"

      emit_operation_started("github.list_issues", args)

      case http_client(opts).get(url, headers(opts)) do
        {:ok, %{status: 200, body: body}} ->
          result = %{"issues" => body, "total_count" => length(body)}
          emit_operation_succeeded("github.list_issues")
          {:ok, result}

        {:ok, %{status: status, body: body}} ->
          body
          |> http_error("github.list_issues", status, %{"owner" => owner, "repo" => repo})
          |> fail_operation("github.list_issues")

        {:error, reason} ->
          fail_operation(
            Error.new(:unavailable, "GitHub API error: #{inspect(reason)}",
              code: "github.unavailable",
              upstream_context: %{"reason" => inspect(reason)}
            ),
            "github.list_issues"
          )
      end
    end
  end

  def run("github.fetch_issue", args, opts) do
    with :ok <- require_args(args, ["owner", "repo", "issue_number"]) do
      owner = args["owner"]
      repo = args["repo"]
      issue_number = args["issue_number"]
      url = "#{@github_api_base}/repos/#{owner}/#{repo}/issues/#{issue_number}"

      emit_operation_started("github.fetch_issue", args)

      case http_client(opts).get(url, headers(opts)) do
        {:ok, %{status: 200, body: response_body}} ->
          emit_operation_succeeded("github.fetch_issue")
          {:ok, response_body}

        {:ok, %{status: status, body: body}} ->
          body
          |> http_error("github.fetch_issue", status, %{
            "owner" => owner,
            "repo" => repo,
            "issue_number" => issue_number
          })
          |> fail_operation("github.fetch_issue")

        {:error, reason} ->
          fail_operation(
            Error.new(:unavailable, "GitHub API error: #{inspect(reason)}",
              code: "github.unavailable",
              upstream_context: %{"reason" => inspect(reason)}
            ),
            "github.fetch_issue"
          )
      end
    end
  end

  def run("github.create_issue", args, opts) do
    with :ok <- require_args(args, ["owner", "repo", "title"]) do
      owner = args["owner"]
      repo = args["repo"]
      title = args["title"]
      body_text = Map.get(args, "body", "")
      labels = Map.get(args, "labels", [])
      assignees = Map.get(args, "assignees", [])

      url = "#{@github_api_base}/repos/#{owner}/#{repo}/issues"

      payload = %{
        "title" => title,
        "body" => body_text,
        "labels" => labels,
        "assignees" => assignees
      }

      emit_operation_started("github.create_issue", args)

      case http_client(opts).post(url, payload, headers(opts)) do
        {:ok, %{status: status, body: response_body}} when status in [200, 201] ->
          result = %{
            "id" => response_body["id"],
            "number" => response_body["number"],
            "url" => response_body["url"],
            "html_url" => response_body["html_url"]
          }

          emit_operation_succeeded("github.create_issue")
          {:ok, result}

        {:ok, %{status: status, body: body}} ->
          body
          |> http_error("github.create_issue", status, %{"owner" => owner, "repo" => repo})
          |> fail_operation("github.create_issue")

        {:error, reason} ->
          fail_operation(
            Error.new(:unavailable, "GitHub API error: #{inspect(reason)}",
              code: "github.unavailable",
              upstream_context: %{"reason" => inspect(reason)}
            ),
            "github.create_issue"
          )
      end
    end
  end

  def run("github.update_issue", args, opts) do
    with :ok <- require_args(args, ["owner", "repo", "issue_number"]) do
      owner = args["owner"]
      repo = args["repo"]
      issue_number = args["issue_number"]
      url = "#{@github_api_base}/repos/#{owner}/#{repo}/issues/#{issue_number}"

      payload =
        args
        |> Map.take(["title", "body", "state", "labels", "assignees"])
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      emit_operation_started("github.update_issue", args)

      case http_client(opts).patch(url, payload, headers(opts)) do
        {:ok, %{status: 200, body: response_body}} ->
          emit_operation_succeeded("github.update_issue")
          {:ok, issue_result(response_body)}

        {:ok, %{status: status, body: body}} ->
          body
          |> http_error("github.update_issue", status, %{
            "owner" => owner,
            "repo" => repo,
            "issue_number" => issue_number
          })
          |> fail_operation("github.update_issue")

        {:error, reason} ->
          fail_operation(
            Error.new(:unavailable, "GitHub API error: #{inspect(reason)}",
              code: "github.unavailable",
              upstream_context: %{"reason" => inspect(reason)}
            ),
            "github.update_issue"
          )
      end
    end
  end

  def run("github.label_issue", args, opts) do
    with :ok <- require_args(args, ["owner", "repo", "issue_number", "labels"]) do
      owner = args["owner"]
      repo = args["repo"]
      issue_number = args["issue_number"]
      labels = args["labels"]
      url = "#{@github_api_base}/repos/#{owner}/#{repo}/issues/#{issue_number}/labels"

      emit_operation_started("github.label_issue", args)

      case http_client(opts).post(url, %{"labels" => labels}, headers(opts)) do
        {:ok, %{status: status, body: response_body}} when status in [200, 201] ->
          emit_operation_succeeded("github.label_issue")
          {:ok, %{"labels" => response_body}}

        {:ok, %{status: status, body: body}} ->
          body
          |> http_error("github.label_issue", status, %{
            "owner" => owner,
            "repo" => repo,
            "issue_number" => issue_number
          })
          |> fail_operation("github.label_issue")

        {:error, reason} ->
          fail_operation(
            Error.new(:unavailable, "GitHub API error: #{inspect(reason)}",
              code: "github.unavailable",
              upstream_context: %{"reason" => inspect(reason)}
            ),
            "github.label_issue"
          )
      end
    end
  end

  def run("github.create_comment", args, opts) do
    with :ok <- require_args(args, ["owner", "repo", "issue_number", "body"]) do
      owner = args["owner"]
      repo = args["repo"]
      issue_number = args["issue_number"]
      body_text = args["body"]

      url = "#{@github_api_base}/repos/#{owner}/#{repo}/issues/#{issue_number}/comments"
      payload = %{"body" => body_text}

      emit_operation_started("github.create_comment", args)

      case http_client(opts).post(url, payload, headers(opts)) do
        {:ok, %{status: status, body: response_body}} when status in [200, 201] ->
          result = %{
            "id" => response_body["id"],
            "url" => response_body["url"],
            "html_url" => response_body["html_url"]
          }

          emit_operation_succeeded("github.create_comment")
          {:ok, result}

        {:ok, %{status: status, body: body}} ->
          body
          |> http_error("github.create_comment", status, %{
            "owner" => owner,
            "repo" => repo,
            "issue_number" => issue_number
          })
          |> fail_operation("github.create_comment")

        {:error, reason} ->
          fail_operation(
            Error.new(:unavailable, "GitHub API error: #{inspect(reason)}",
              code: "github.unavailable",
              upstream_context: %{"reason" => inspect(reason)}
            ),
            "github.create_comment"
          )
      end
    end
  end

  def run("github.update_comment", args, opts) do
    with :ok <- require_args(args, ["owner", "repo", "comment_id", "body"]) do
      owner = args["owner"]
      repo = args["repo"]
      comment_id = args["comment_id"]
      body_text = args["body"]
      url = "#{@github_api_base}/repos/#{owner}/#{repo}/issues/comments/#{comment_id}"
      payload = %{"body" => body_text}

      emit_operation_started("github.update_comment", args)

      case http_client(opts).patch(url, payload, headers(opts)) do
        {:ok, %{status: 200, body: response_body}} ->
          emit_operation_succeeded("github.update_comment")
          {:ok, comment_result(response_body)}

        {:ok, %{status: status, body: body}} ->
          body
          |> http_error("github.update_comment", status, %{
            "owner" => owner,
            "repo" => repo,
            "comment_id" => comment_id
          })
          |> fail_operation("github.update_comment")

        {:error, reason} ->
          fail_operation(
            Error.new(:unavailable, "GitHub API error: #{inspect(reason)}",
              code: "github.unavailable",
              upstream_context: %{"reason" => inspect(reason)}
            ),
            "github.update_comment"
          )
      end
    end
  end

  def run("github.close_issue", args, opts) do
    run("github.update_issue", Map.put(args, "state", "closed"), opts)
  end

  def run(operation_id, _args, _opts) do
    {:error, Error.new(:unsupported, "Unknown operation: #{operation_id}")}
  end

  @impl true
  def handle_trigger("github.webhook.push", payload) do
    event_type = get_in(payload, ["headers", "x-github-event"]) || "unknown"
    delivery_id = get_in(payload, ["headers", "x-github-delivery"])

    {:ok,
     %{
       "event_type" => event_type,
       "delivery_id" => delivery_id,
       "payload" => Map.get(payload, "body", %{})
     }}
  end

  def handle_trigger(trigger_id, _payload) do
    {:error, Error.new(:unsupported, "Unknown trigger: #{trigger_id}")}
  end

  defp http_client(opts) do
    case Keyword.get(opts, :http_client) do
      nil -> configured_http_client()
      client -> client
    end
  end

  defp configured_http_client do
    legacy_config = Application.get_env(:jido_integration, __MODULE__, [])
    package_config = Application.get_env(:jido_integration_github, __MODULE__, [])

    legacy_config
    |> Keyword.merge(package_config)
    |> Keyword.get(:http_client, Jido.Integration.Connectors.GitHub.DefaultClient)
  end

  defp headers(opts) do
    token = Keyword.get(opts, :token, "")

    [
      {"accept", "application/vnd.github+json"},
      {"authorization", "Bearer #{token}"},
      {"x-github-api-version", "2022-11-28"},
      {"user-agent", "jido-integration-github/0.1.0"}
    ]
  end

  defp rate_limited?(body) when is_map(body) do
    Map.get(body, "message", "") |> String.contains?("rate limit")
  end

  defp rate_limited?(_), do: false

  defp require_args(args, required_keys) do
    missing = Enum.filter(required_keys, &(not Map.has_key?(args, &1)))

    case missing do
      [] ->
        :ok

      _ ->
        {:error,
         Error.new(:invalid_request, "Missing required args: #{Enum.join(missing, ", ")}",
           code: "github.invalid_request"
         )}
    end
  end

  defp http_error(body, _operation_id, 401, context) do
    Error.new(:auth_failed, "GitHub authentication failed",
      code: "github.auth_failed",
      upstream_context: error_context(401, body, context)
    )
  end

  defp http_error(body, _operation_id, 403, context) do
    if rate_limited?(body) do
      Error.new(:rate_limited, "GitHub rate limit exceeded",
        code: "github.rate_limited",
        upstream_context: error_context(403, body, context)
      )
    else
      Error.new(:auth_failed, "GitHub access denied",
        code: "github.auth_failed",
        upstream_context: error_context(403, body, context)
      )
    end
  end

  defp http_error(body, _operation_id, 429, context) do
    Error.new(:rate_limited, "GitHub rate limit exceeded",
      code: "github.rate_limited",
      upstream_context: error_context(429, body, context)
    )
  end

  defp http_error(body, operation_id, 404, context) do
    not_found_error(operation_id, 404, body, context)
  end

  defp http_error(body, operation_id, status, context) when status in [400, 422] do
    Error.new(:invalid_request, validation_message(operation_id, body),
      code: "github.invalid_request",
      upstream_context: error_context(status, body, context)
    )
  end

  defp http_error(body, _operation_id, status, context) when status >= 500 do
    Error.new(:unavailable, "GitHub API unavailable (status #{status})",
      code: "github.unavailable",
      upstream_context: error_context(status, body, context)
    )
  end

  defp http_error(body, _operation_id, status, context) do
    Error.new(:unavailable, "Unexpected GitHub response status: #{status}",
      code: "github.unavailable",
      upstream_context: error_context(status, body, context)
    )
  end

  defp not_found_error(
         "github.list_issues",
         status,
         body,
         %{"owner" => owner, "repo" => repo} = context
       ) do
    Error.new(:invalid_request, "Repository not found: #{owner}/#{repo}",
      code: "github.invalid_request",
      upstream_context: error_context(status, body, context)
    )
  end

  defp not_found_error(
         "github.create_issue",
         status,
         body,
         %{"owner" => owner, "repo" => repo} = context
       ) do
    Error.new(:invalid_request, "Repository not found: #{owner}/#{repo}",
      code: "github.invalid_request",
      upstream_context: error_context(status, body, context)
    )
  end

  defp not_found_error(
         "github.create_comment",
         status,
         body,
         %{"owner" => owner, "repo" => repo, "issue_number" => issue_number} = context
       ) do
    Error.new(:invalid_request, "Issue not found: #{owner}/#{repo}##{issue_number}",
      code: "github.invalid_request",
      upstream_context: error_context(status, body, context)
    )
  end

  defp not_found_error(
         operation_id,
         status,
         body,
         %{"owner" => owner, "repo" => repo, "issue_number" => issue_number} = context
       )
       when operation_id in ["github.fetch_issue", "github.update_issue", "github.label_issue"] do
    Error.new(:invalid_request, "Issue not found: #{owner}/#{repo}##{issue_number}",
      code: "github.invalid_request",
      upstream_context: error_context(status, body, context)
    )
  end

  defp not_found_error(
         "github.update_comment",
         status,
         body,
         %{"owner" => owner, "repo" => repo, "comment_id" => comment_id} = context
       ) do
    Error.new(:invalid_request, "Comment not found: #{owner}/#{repo}##{comment_id}",
      code: "github.invalid_request",
      upstream_context: error_context(status, body, context)
    )
  end

  defp validation_message("github.create_issue", body) do
    "Validation failed: #{inspect(Map.get(body, "errors", []))}"
  end

  defp validation_message(operation_id, body)
       when operation_id in ["github.update_issue", "github.update_comment", "github.label_issue"] do
    "Validation failed: #{inspect(Map.get(body, "errors", []))}"
  end

  defp validation_message(operation_id, _body) do
    "GitHub rejected #{operation_id}"
  end

  defp issue_result(response_body) do
    %{
      "id" => response_body["id"],
      "number" => response_body["number"],
      "url" => response_body["url"],
      "html_url" => response_body["html_url"],
      "state" => response_body["state"],
      "title" => response_body["title"],
      "labels" => response_body["labels"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp comment_result(response_body) do
    %{
      "id" => response_body["id"],
      "url" => response_body["url"],
      "html_url" => response_body["html_url"],
      "body" => response_body["body"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp error_context(status, body, context) do
    Map.merge(context, %{
      "status" => status,
      "body" => body
    })
  end

  defp fail_operation(%Error{} = error, operation_id) do
    emit_operation_failed(operation_id, to_string(error.class))
    {:error, error}
  end

  defp emit_operation_started(operation_id, args) do
    :telemetry.execute(
      [:jido, :integration, :operation, :started],
      %{},
      %{connector_id: "github", operation_id: operation_id, args: args}
    )
  end

  defp emit_operation_succeeded(operation_id) do
    :telemetry.execute(
      [:jido, :integration, :operation, :succeeded],
      %{},
      %{connector_id: "github", operation_id: operation_id}
    )
  end

  defp emit_operation_failed(operation_id, reason) do
    :telemetry.execute(
      [:jido, :integration, :operation, :failed],
      %{},
      %{connector_id: "github", operation_id: operation_id, reason: reason}
    )
  end
end
