defmodule Jido.Integration.V2.Connectors.GitHub.Fixtures do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Pristine.SDK.Response

  @run_id "run-github-test"
  @attempt_id "#{@run_id}:1"
  @subject "octocat"
  @credential_ref_id "cred-github-test"
  @lease_id "lease-github-test"
  @access_token "gho_test"
  @repo "agentjido/jido_integration_v2"

  @capability_specs [
    %{
      capability_id: "github.comment.create",
      event_type: "connector.github.comment.created",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/comment_create.term",
      input: %{repo: @repo, issue_number: 42, body: "Add a deterministic review note"}
    },
    %{
      capability_id: "github.comment.update",
      event_type: "connector.github.comment.updated",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/comment_update.term",
      input: %{repo: @repo, comment_id: 901, body: "Edited deterministic review note"}
    },
    %{
      capability_id: "github.issue.close",
      event_type: "connector.github.issue.closed",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/issue_close.term",
      input: %{repo: @repo, issue_number: 42}
    },
    %{
      capability_id: "github.issue.create",
      event_type: "connector.github.issue.created",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/issue_create.term",
      input: %{repo: @repo, title: "Ship the platform package", body: "Direct runtime slice"}
    },
    %{
      capability_id: "github.issue.fetch",
      event_type: "connector.github.issue.fetched",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/issue_fetch.term",
      input: %{repo: @repo, issue_number: 42}
    },
    %{
      capability_id: "github.issue.label",
      event_type: "connector.github.issue.labeled",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/issue_label.term",
      input: %{repo: @repo, issue_number: 42, labels: ["platform", "triaged"]}
    },
    %{
      capability_id: "github.issue.list",
      event_type: "connector.github.issue.listed",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/issue_list.term",
      input: %{repo: @repo, state: "open", per_page: 2, page: 1}
    },
    %{
      capability_id: "github.issue.update",
      event_type: "connector.github.issue.updated",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/issue_update.term",
      input: %{
        repo: @repo,
        issue_number: 42,
        title: "Ship the platform package now",
        body: "Expanded deterministic review surface",
        state: "open",
        labels: ["platform", "v2"],
        assignees: ["octocat"]
      }
    }
  ]

  @spec specs() :: [map()]
  def specs do
    Enum.map(@capability_specs, fn spec ->
      Map.put(
        spec,
        :output,
        expected_output(spec.capability_id, spec.input, @subject, @access_token)
      )
    end)
  end

  @spec published_capability_ids() :: [String.t()]
  def published_capability_ids do
    Enum.map(@capability_specs, & &1.capability_id)
  end

  @spec access_token() :: String.t()
  def access_token, do: @access_token

  @spec auth_binding(String.t()) :: String.t()
  def auth_binding(token \\ @access_token), do: ArtifactBuilder.digest(token)

  @spec credential_ref(String.t()) :: CredentialRef.t()
  def credential_ref(subject \\ @subject) do
    CredentialRef.new!(%{
      id: @credential_ref_id,
      subject: subject,
      scopes: ["repo"]
    })
  end

  @spec credential_lease(String.t(), String.t()) :: CredentialLease.t()
  def credential_lease(subject \\ @subject, token \\ @access_token) do
    CredentialLease.new!(%{
      lease_id: @lease_id,
      credential_ref_id: @credential_ref_id,
      subject: subject,
      scopes: ["repo"],
      payload: %{access_token: token},
      issued_at: ~U[2026-03-12 00:00:00Z],
      expires_at: ~U[2026-03-12 00:05:00Z]
    })
  end

  @spec client_opts(pid() | nil, keyword()) :: keyword()
  def client_opts(test_pid, opts \\ []) do
    transport_opts =
      []
      |> maybe_put(:test_pid, test_pid)
      |> maybe_put(:response, Keyword.get(opts, :response))

    [
      transport: Jido.Integration.V2.Connectors.GitHub.FixtureTransport,
      transport_opts: transport_opts
    ]
  end

  @spec execution_context(String.t(), keyword()) :: map()
  def execution_context(_capability_id, opts \\ []) do
    %{
      run_id: @run_id,
      attempt_id: @attempt_id,
      credential_ref: credential_ref(),
      credential_lease: credential_lease(),
      policy_inputs: %{
        execution: %{
          runtime_class: :direct,
          sandbox: %{
            level: :standard,
            egress: :restricted,
            approvals: :auto,
            allowed_tools: []
          }
        }
      },
      opts: %{
        github_client: Keyword.get(opts, :github_client, client_opts(nil))
      }
    }
  end

  @spec input_for(String.t()) :: map()
  def input_for(capability_id) do
    specs()
    |> Enum.find(&(&1.capability_id == capability_id))
    |> Map.fetch!(:input)
  end

  @spec expected_output(String.t(), map(), String.t(), String.t()) :: map()
  def expected_output("github.issue.list", input, subject, token) do
    state = Map.get(input, :state, "open")
    page = Map.get(input, :page, 1)
    per_page = Map.get(input, :per_page, 30)

    issues =
      for offset <- 0..(per_page - 1), per_page > 0 do
        issue_number = issue_seed(input.repo, state, page, offset)

        %{
          repo: input.repo,
          issue_number: issue_number,
          title: "Deterministic #{state} issue #{issue_number}",
          state: state,
          labels: label_set(issue_number)
        }
      end

    %{
      repo: input.repo,
      state: state,
      page: page,
      per_page: per_page,
      total_count: length(issues),
      issues: issues,
      listed_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.issue.fetch", input, subject, token) do
    %{
      repo: input.repo,
      issue_number: input.issue_number,
      title: "Issue #{input.issue_number} in #{input.repo}",
      body: "Deterministic issue payload for #{input.repo}##{input.issue_number}",
      state: issue_state(input.issue_number),
      labels: label_set(input.issue_number),
      fetched_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.issue.create", input, subject, token) do
    %{
      repo: input.repo,
      issue_number: create_issue_number(input.repo, input.title, Map.get(input, :body)),
      title: input.title,
      body: Map.get(input, :body),
      state: "open",
      labels: Map.get(input, :labels, []),
      assignees: Map.get(input, :assignees, []),
      opened_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.issue.update", input, subject, token) do
    %{
      repo: input.repo,
      issue_number: input.issue_number,
      title: input.title,
      body: input.body,
      state: input.state,
      labels: input.labels,
      assignees: input.assignees,
      updated_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.issue.label", input, subject, token) do
    %{
      repo: input.repo,
      issue_number: input.issue_number,
      labels: input.labels,
      labeled_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.issue.close", input, subject, token) do
    %{
      repo: input.repo,
      issue_number: input.issue_number,
      state: "closed",
      closed_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.comment.create", input, subject, token) do
    %{
      repo: input.repo,
      issue_number: input.issue_number,
      comment_id: comment_seed(input.repo, input.issue_number, input.body),
      body: input.body,
      created_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.comment.update", input, subject, token) do
    %{
      repo: input.repo,
      comment_id: input.comment_id,
      body: input.body,
      updated_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  @spec assert_request(String.t(), map()) :: true
  def assert_request(capability_id, request) do
    input = input_for(capability_id)
    uri = URI.parse(request.url)

    expect_equal(
      request.headers["Authorization"],
      "Bearer #{@access_token}",
      "authorization header"
    )

    expect_equal(request.headers["Accept"], "application/vnd.github+json", "accept header")

    expect_equal(
      request.headers["X-GitHub-Api-Version"],
      GitHubEx.Client.default_api_version(),
      "GitHub API version header"
    )

    case capability_id do
      "github.issue.list" ->
        expect_equal(request.method, :get, "request method")
        expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/issues", "request path")
        expect_equal(uri.query, "page=1&per_page=2&state=open", "query string")

      "github.issue.fetch" ->
        expect_equal(request.method, :get, "request method")
        expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/issues/42", "request path")

      "github.issue.create" ->
        expect_equal(request.method, :post, "request method")
        expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/issues", "request path")

        expect_equal(
          Jason.decode!(request.body),
          %{"title" => input.title, "body" => input.body},
          "request body"
        )

      "github.issue.update" ->
        expect_equal(request.method, :patch, "request method")
        expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/issues/42", "request path")

        expect_equal(
          Jason.decode!(request.body),
          %{
            "assignees" => input.assignees,
            "body" => input.body,
            "labels" => input.labels,
            "state" => input.state,
            "title" => input.title
          },
          "request body"
        )

      "github.issue.label" ->
        expect_equal(request.method, :post, "request method")

        expect_equal(
          uri.path,
          "/repos/agentjido/jido_integration_v2/issues/42/labels",
          "request path"
        )

        expect_equal(Jason.decode!(request.body), %{"labels" => input.labels}, "request body")

      "github.issue.close" ->
        expect_equal(request.method, :patch, "request method")
        expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/issues/42", "request path")
        expect_equal(Jason.decode!(request.body), %{"state" => "closed"}, "request body")

      "github.comment.create" ->
        expect_equal(request.method, :post, "request method")

        expect_equal(
          uri.path,
          "/repos/agentjido/jido_integration_v2/issues/42/comments",
          "request path"
        )

        expect_equal(Jason.decode!(request.body), %{"body" => input.body}, "request body")

      "github.comment.update" ->
        expect_equal(request.method, :patch, "request method")

        expect_equal(
          uri.path,
          "/repos/agentjido/jido_integration_v2/issues/comments/901",
          "request path"
        )

        expect_equal(Jason.decode!(request.body), %{"body" => input.body}, "request body")
    end

    true
  end

  @spec response_for_request(map(), map()) :: {:ok, Response.t()}
  def response_for_request(request, _context \\ %{}) do
    uri = URI.parse(request.url)

    case {request.method, path_segments(uri.path)} do
      {:get, ["repos", owner, repo, "issues"]} ->
        repo = repo_name(owner, repo)
        params = URI.decode_query(uri.query || "")
        state = Map.get(params, "state", "open")
        page = parse_positive_integer(Map.get(params, "page")) || 1
        per_page = parse_positive_integer(Map.get(params, "per_page")) || 30
        sdk_response(list_issues_body(repo, state, page, per_page))

      {:get, ["repos", owner, repo, "issues", issue_number]} ->
        repo = repo_name(owner, repo)
        issue_number = String.to_integer(issue_number)
        sdk_response(fetch_issue_body(repo, issue_number))

      {:post, ["repos", owner, repo, "issues"]} ->
        repo = repo_name(owner, repo)
        body = decode_request_body(request)
        sdk_response(create_issue_body(repo, body))

      {:patch, ["repos", owner, repo, "issues", issue_number]} ->
        repo = repo_name(owner, repo)
        issue_number = String.to_integer(issue_number)
        body = decode_request_body(request)
        sdk_response(update_issue_body(repo, issue_number, body))

      {:post, ["repos", owner, repo, "issues", issue_number, "labels"]} ->
        repo = repo_name(owner, repo)
        issue_number = String.to_integer(issue_number)
        body = decode_request_body(request)
        sdk_response(label_issue_body(repo, issue_number, body))

      {:post, ["repos", owner, repo, "issues", issue_number, "comments"]} ->
        repo = repo_name(owner, repo)
        issue_number = String.to_integer(issue_number)
        body = decode_request_body(request)
        sdk_response(create_comment_body(repo, issue_number, body))

      {:patch, ["repos", owner, repo, "issues", "comments", comment_id]} ->
        repo = repo_name(owner, repo)
        comment_id = String.to_integer(comment_id)
        body = decode_request_body(request)
        sdk_response(update_comment_body(repo, comment_id, body))

      _other ->
        sdk_response(
          %{"message" => "missing github fixture for #{request.method} #{uri.path}"},
          404
        )
    end
  end

  @spec not_found_response() :: (map(), map() -> {:ok, Response.t()})
  def not_found_response do
    fn _request, _context ->
      sdk_response(
        %{
          "message" => "Not Found",
          "documentation_url" => "https://docs.github.com/rest/issues/issues#get-an-issue",
          "token" => @access_token,
          "errors" => [%{"access_token" => @access_token}]
        },
        404,
        %{
          "authorization" => "Bearer #{@access_token}",
          "x-github-request-id" => "req-github-missing"
        }
      )
    end
  end

  defp list_issues_body(repo, state, page, per_page) do
    for offset <- 0..(per_page - 1), per_page > 0 do
      issue_number = issue_seed(repo, state, page, offset)

      %{
        "number" => issue_number,
        "title" => "Deterministic #{state} issue #{issue_number}",
        "state" => state,
        "labels" => Enum.map(label_set(issue_number), &%{"name" => &1})
      }
    end
  end

  defp fetch_issue_body(repo, issue_number) do
    %{
      "number" => issue_number,
      "title" => "Issue #{issue_number} in #{repo}",
      "body" => "Deterministic issue payload for #{repo}##{issue_number}",
      "state" => issue_state(issue_number),
      "labels" => Enum.map(label_set(issue_number), &%{"name" => &1})
    }
  end

  defp create_issue_body(repo, body) do
    title = Map.get(body, "title")
    issue_body = Map.get(body, "body")
    labels = Map.get(body, "labels", [])
    assignees = Map.get(body, "assignees", [])

    %{
      "number" => create_issue_number(repo, title, issue_body),
      "title" => title,
      "body" => issue_body,
      "state" => "open",
      "labels" => Enum.map(labels, &%{"name" => &1}),
      "assignees" => Enum.map(assignees, &%{"login" => &1})
    }
  end

  defp update_issue_body(repo, issue_number, body) do
    %{
      "number" => issue_number,
      "title" => Map.get(body, "title", "Issue #{issue_number} in #{repo}"),
      "body" => Map.get(body, "body", "Deterministic issue payload for #{repo}##{issue_number}"),
      "state" => Map.get(body, "state", issue_state(issue_number)),
      "labels" =>
        body
        |> Map.get("labels", label_set(issue_number))
        |> Enum.map(&%{"name" => &1}),
      "assignees" =>
        body
        |> Map.get("assignees", [])
        |> Enum.map(&%{"login" => &1})
    }
  end

  defp label_issue_body(_repo, _issue_number, body) do
    body
    |> Map.get("labels", [])
    |> Enum.map(&%{"name" => &1})
  end

  defp create_comment_body(repo, issue_number, body) do
    comment_body = Map.get(body, "body")

    %{
      "id" => comment_seed(repo, issue_number, comment_body),
      "body" => comment_body
    }
  end

  defp update_comment_body(_repo, comment_id, body) do
    %{
      "id" => comment_id,
      "body" => Map.get(body, "body")
    }
  end

  defp decode_request_body(request) do
    case Map.get(request, :body) do
      nil -> %{}
      "" -> %{}
      body -> Jason.decode!(body)
    end
  end

  defp sdk_response(body, status \\ 200, headers \\ %{}) do
    {:ok, Response.new(status: status, headers: headers, body: Jason.encode!(body))}
  end

  defp repo_name(owner, repo), do: owner <> "/" <> repo

  defp path_segments(path) do
    path
    |> String.split("/", trim: true)
  end

  defp parse_positive_integer(nil), do: nil

  defp parse_positive_integer(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _other -> nil
    end
  end

  defp issue_seed(repo, state, page, offset) do
    :erlang.phash2({repo, state, page, offset}, 90_000) + 1
  end

  defp create_issue_number(repo, title, body) do
    :erlang.phash2({repo, title, body}, 10_000)
  end

  defp comment_seed(repo, issue_number, body) do
    :erlang.phash2({repo, issue_number, body}, 100_000)
  end

  defp issue_state(issue_number) when rem(issue_number, 2) == 0, do: "open"
  defp issue_state(_issue_number), do: "closed"

  defp label_set(issue_number) when rem(issue_number, 2) == 0, do: ["bug", "triaged"]
  defp label_set(_issue_number), do: ["enhancement"]

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp expect_equal(actual, expected, _label) when actual == expected, do: :ok

  defp expect_equal(actual, expected, label) do
    raise """
    unexpected #{label}
    expected: #{inspect(expected)}
    actual: #{inspect(actual)}
    """
  end
end
