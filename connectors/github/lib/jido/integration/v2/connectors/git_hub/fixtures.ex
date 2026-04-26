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
  @profile_id "personal_access_token"
  @access_token "gho_test"
  @repo "agentjido/jido_integration_v2"
  @pull_number 17
  @head_ref "source-backed-work"
  @base_ref "main"
  @head_sha "f00dbabe1234567890abcdef1234567890abcdef"
  @base_sha "0ddba11adeadbeef1234567890abcdef12345678"

  @capability_specs [
    %{
      capability_id: "github.check_runs.list_for_ref",
      event_type: "connector.github.check_runs.listed",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/check_runs_list_for_ref.term",
      input: %{repo: @repo, ref: @head_sha, status: "completed", per_page: 2, page: 1}
    },
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
      capability_id: "github.commit.statuses.get_combined",
      event_type: "connector.github.commit.statuses.combined_fetched",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/commit_statuses_get_combined.term",
      input: %{repo: @repo, ref: @head_sha, per_page: 2, page: 1}
    },
    %{
      capability_id: "github.commit.statuses.list",
      event_type: "connector.github.commit.statuses.listed",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/commit_statuses_list.term",
      input: %{repo: @repo, ref: @head_sha, per_page: 2, page: 1}
    },
    %{
      capability_id: "github.commits.list",
      event_type: "connector.github.commits.listed",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/commits_list.term",
      input: %{repo: @repo, sha: @base_ref, path: "lib", per_page: 2, page: 1}
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
    },
    %{
      capability_id: "github.pr.create",
      event_type: "connector.github.pr.created",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/pr_create.term",
      input: %{
        repo: @repo,
        title: "Source-backed GitHub connector parity",
        body: "Open PR through the governed direct runtime",
        head: @head_ref,
        base: @base_ref,
        draft: true
      }
    },
    %{
      capability_id: "github.pr.fetch",
      event_type: "connector.github.pr.fetched",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/pr_fetch.term",
      input: %{repo: @repo, pull_number: @pull_number}
    },
    %{
      capability_id: "github.pr.list",
      event_type: "connector.github.pr.listed",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/pr_list.term",
      input: %{repo: @repo, state: "all", per_page: 2, page: 1}
    },
    %{
      capability_id: "github.pr.review.create",
      event_type: "connector.github.pr.review.created",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/pr_review_create.term",
      input: %{
        repo: @repo,
        pull_number: @pull_number,
        body: "Connector parity review",
        event: "COMMENT"
      }
    },
    %{
      capability_id: "github.pr.review_comment.create",
      event_type: "connector.github.pr.review_comment.created",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/pr_review_comment_create.term",
      input: %{
        repo: @repo,
        pull_number: @pull_number,
        body: "Inline connector parity note",
        commit_id: @head_sha,
        path: "lib/source.ex",
        line: 12,
        side: "RIGHT"
      }
    },
    %{
      capability_id: "github.pr.review_comments.list",
      event_type: "connector.github.pr.review_comments.listed",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/pr_review_comments_list.term",
      input: %{
        repo: @repo,
        pull_number: @pull_number,
        sort: "created",
        direction: "asc",
        per_page: 2,
        page: 1
      }
    },
    %{
      capability_id: "github.pr.reviews.list",
      event_type: "connector.github.pr.reviews.listed",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/pr_reviews_list.term",
      input: %{repo: @repo, pull_number: @pull_number, per_page: 2, page: 1}
    },
    %{
      capability_id: "github.pr.update",
      event_type: "connector.github.pr.updated",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/pr_update.term",
      input: %{
        repo: @repo,
        pull_number: @pull_number,
        title: "Source-backed GitHub connector parity updated",
        body: "Updated through the governed direct runtime",
        state: "open",
        base: @base_ref,
        maintainer_can_modify: true
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
      profile_id: @profile_id,
      subject: subject,
      scopes: ["repo"],
      lease_fields: ["access_token"]
    })
  end

  @spec credential_lease(String.t(), String.t()) :: CredentialLease.t()
  def credential_lease(subject \\ @subject, token \\ @access_token) do
    CredentialLease.new!(%{
      lease_id: @lease_id,
      credential_ref_id: @credential_ref_id,
      profile_id: @profile_id,
      subject: subject,
      scopes: ["repo"],
      payload: %{access_token: token},
      lease_fields: ["access_token"],
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
  def expected_output("github.check_runs.list_for_ref", input, subject, token) do
    check_runs = check_run_summaries(input.repo, input.ref)

    %{
      repo: input.repo,
      ref: input.ref,
      total_count: length(check_runs),
      check_runs: check_runs,
      listed_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.commit.statuses.get_combined", input, subject, token) do
    statuses = commit_status_summaries(input.repo, input.ref)

    %{
      repo: input.repo,
      ref: input.ref,
      sha: input.ref,
      state: "success",
      total_count: length(statuses),
      statuses: statuses,
      fetched_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.commit.statuses.list", input, subject, token) do
    statuses = commit_status_summaries(input.repo, input.ref)

    %{
      repo: input.repo,
      ref: input.ref,
      total_count: length(statuses),
      statuses: statuses,
      listed_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.commits.list", input, subject, token) do
    commits = commit_summaries(input.repo, Map.get(input, :sha, @base_ref))

    %{
      repo: input.repo,
      sha: Map.get(input, :sha),
      path: Map.get(input, :path),
      page: Map.get(input, :page, 1),
      per_page: Map.get(input, :per_page, 30),
      total_count: length(commits),
      commits: commits,
      listed_by: subject,
      auth_binding: auth_binding(token)
    }
  end

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

  def expected_output("github.pr.create", input, subject, token) do
    pull =
      pr_summary(input.repo, @pull_number, input.title, input.body, %{
        "head" => %{"ref" => input.head, "sha" => @head_sha},
        "base" => %{"ref" => input.base, "sha" => @base_sha},
        "draft" => Map.get(input, :draft, false)
      })

    Map.merge(pull, %{
      opened_by: subject,
      auth_binding: auth_binding(token)
    })
  end

  def expected_output("github.pr.fetch", input, subject, token) do
    input.repo
    |> pr_summary(
      input.pull_number,
      "PR #{input.pull_number} in #{input.repo}",
      "Deterministic PR body",
      %{}
    )
    |> Map.merge(%{fetched_by: subject, auth_binding: auth_binding(token)})
  end

  def expected_output("github.pr.list", input, subject, token) do
    pull_requests = [
      pr_summary(
        input.repo,
        @pull_number,
        "PR #{@pull_number} in #{input.repo}",
        "Deterministic PR body",
        %{}
      )
    ]

    %{
      repo: input.repo,
      state: input.state,
      page: input.page,
      per_page: input.per_page,
      total_count: length(pull_requests),
      pull_requests: pull_requests,
      listed_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.pr.update", input, subject, token) do
    input.repo
    |> pr_summary(input.pull_number, input.title, input.body, %{
      "state" => input.state,
      "base" => %{"ref" => input.base, "sha" => @base_sha},
      "maintainer_can_modify" => input.maintainer_can_modify
    })
    |> Map.merge(%{updated_by: subject, auth_binding: auth_binding(token)})
  end

  def expected_output("github.pr.reviews.list", input, subject, token) do
    reviews = review_summaries(input.repo, input.pull_number)

    %{
      repo: input.repo,
      pull_number: input.pull_number,
      total_count: length(reviews),
      reviews: reviews,
      listed_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.pr.review_comments.list", input, subject, token) do
    comments = review_comment_summaries(input.repo, input.pull_number)

    %{
      repo: input.repo,
      pull_number: input.pull_number,
      total_count: length(comments),
      comments: comments,
      listed_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.pr.review.create", input, subject, token) do
    review = created_review_summary(input.repo, input.pull_number, input.body, input.event)

    %{
      repo: input.repo,
      pull_number: input.pull_number,
      review: review,
      created_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.pr.review_comment.create", input, subject, token) do
    comment =
      created_review_comment_summary(
        input.repo,
        input.pull_number,
        input.body,
        input.commit_id,
        input.path
      )

    %{
      repo: input.repo,
      pull_number: input.pull_number,
      comment: comment,
      created_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  @spec assert_request(String.t(), map()) :: true
  def assert_request(capability_id, request) do
    input = input_for(capability_id)
    uri = URI.parse(request.url)

    assert_common_headers(request)
    assert_capability_request(capability_id, request, uri, input)
    true
  end

  defp assert_common_headers(request) do
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
  end

  defp assert_capability_request("github.check_runs.list_for_ref", request, uri, _input) do
    expect_equal(request.method, :get, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/commits/#{@head_sha}/check-runs",
      "request path"
    )

    expect_equal(uri.query, "page=1&per_page=2&status=completed", "query string")
  end

  defp assert_capability_request("github.issue.list", request, uri, _input) do
    expect_equal(request.method, :get, "request method")
    expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/issues", "request path")
    expect_equal(uri.query, "page=1&per_page=2&state=open", "query string")
  end

  defp assert_capability_request("github.commit.statuses.get_combined", request, uri, _input) do
    expect_equal(request.method, :get, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/commits/#{@head_sha}/status",
      "request path"
    )

    expect_equal(uri.query, "page=1&per_page=2", "query string")
  end

  defp assert_capability_request("github.commit.statuses.list", request, uri, _input) do
    expect_equal(request.method, :get, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/commits/#{@head_sha}/statuses",
      "request path"
    )

    expect_equal(uri.query, "page=1&per_page=2", "query string")
  end

  defp assert_capability_request("github.commits.list", request, uri, _input) do
    expect_equal(request.method, :get, "request method")
    expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/commits", "request path")
    expect_equal(uri.query, "page=1&path=lib&per_page=2&sha=main", "query string")
  end

  defp assert_capability_request("github.issue.fetch", request, uri, _input) do
    expect_equal(request.method, :get, "request method")
    expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/issues/42", "request path")
  end

  defp assert_capability_request("github.issue.create", request, uri, input) do
    expect_equal(request.method, :post, "request method")
    expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/issues", "request path")

    expect_equal(
      Jason.decode!(request.body),
      %{"title" => input.title, "body" => input.body},
      "request body"
    )
  end

  defp assert_capability_request("github.issue.update", request, uri, input) do
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
  end

  defp assert_capability_request("github.issue.label", request, uri, input) do
    expect_equal(request.method, :post, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/issues/42/labels",
      "request path"
    )

    expect_equal(Jason.decode!(request.body), %{"labels" => input.labels}, "request body")
  end

  defp assert_capability_request("github.issue.close", request, uri, _input) do
    expect_equal(request.method, :patch, "request method")
    expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/issues/42", "request path")
    expect_equal(Jason.decode!(request.body), %{"state" => "closed"}, "request body")
  end

  defp assert_capability_request("github.comment.create", request, uri, input) do
    expect_equal(request.method, :post, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/issues/42/comments",
      "request path"
    )

    expect_equal(Jason.decode!(request.body), %{"body" => input.body}, "request body")
  end

  defp assert_capability_request("github.comment.update", request, uri, input) do
    expect_equal(request.method, :patch, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/issues/comments/901",
      "request path"
    )

    expect_equal(Jason.decode!(request.body), %{"body" => input.body}, "request body")
  end

  defp assert_capability_request("github.pr.create", request, uri, input) do
    expect_equal(request.method, :post, "request method")
    expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/pulls", "request path")

    expect_equal(
      Jason.decode!(request.body),
      %{
        "base" => input.base,
        "body" => input.body,
        "draft" => input.draft,
        "head" => input.head,
        "title" => input.title
      },
      "request body"
    )
  end

  defp assert_capability_request("github.pr.fetch", request, uri, _input) do
    expect_equal(request.method, :get, "request method")
    expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/pulls/17", "request path")
  end

  defp assert_capability_request("github.pr.list", request, uri, _input) do
    expect_equal(request.method, :get, "request method")
    expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/pulls", "request path")
    expect_equal(uri.query, "page=1&per_page=2&state=all", "query string")
  end

  defp assert_capability_request("github.pr.update", request, uri, input) do
    expect_equal(request.method, :patch, "request method")
    expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/pulls/17", "request path")

    expect_equal(
      Jason.decode!(request.body),
      %{
        "base" => input.base,
        "body" => input.body,
        "maintainer_can_modify" => input.maintainer_can_modify,
        "state" => input.state,
        "title" => input.title
      },
      "request body"
    )
  end

  defp assert_capability_request("github.pr.reviews.list", request, uri, _input) do
    expect_equal(request.method, :get, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/pulls/17/reviews",
      "request path"
    )

    expect_equal(uri.query, "page=1&per_page=2", "query string")
  end

  defp assert_capability_request("github.pr.review_comments.list", request, uri, _input) do
    expect_equal(request.method, :get, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/pulls/17/comments",
      "request path"
    )

    expect_equal(
      uri.query,
      "direction=asc&page=1&per_page=2&sort=created",
      "query string"
    )
  end

  defp assert_capability_request("github.pr.review.create", request, uri, input) do
    expect_equal(request.method, :post, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/pulls/17/reviews",
      "request path"
    )

    expect_equal(
      Jason.decode!(request.body),
      %{"body" => input.body, "event" => input.event},
      "request body"
    )
  end

  defp assert_capability_request("github.pr.review_comment.create", request, uri, input) do
    expect_equal(request.method, :post, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/pulls/17/comments",
      "request path"
    )

    expect_equal(
      Jason.decode!(request.body),
      %{
        "body" => input.body,
        "commit_id" => input.commit_id,
        "line" => input.line,
        "path" => input.path,
        "side" => input.side
      },
      "request body"
    )
  end

  @spec response_for_request(map(), map()) :: {:ok, Response.t()}
  def response_for_request(request, _context \\ %{}) do
    uri = URI.parse(request.url)
    segments = path_segments(uri.path)

    case request.method do
      :get -> response_for_get(request, uri, segments)
      :post -> response_for_post(request, uri, segments)
      :patch -> response_for_patch(request, uri, segments)
      _other -> missing_fixture_response(request, uri)
    end
  end

  defp response_for_get(_request, uri, ["repos", owner, repo, "issues"]) do
    repo = repo_name(owner, repo)
    params = URI.decode_query(uri.query || "")
    state = Map.get(params, "state", "open")
    page = parse_positive_integer(Map.get(params, "page")) || 1
    per_page = parse_positive_integer(Map.get(params, "per_page")) || 30
    sdk_response(list_issues_body(repo, state, page, per_page))
  end

  defp response_for_get(_request, uri, ["repos", owner, repo, "pulls"]) do
    repo = repo_name(owner, repo)
    _params = URI.decode_query(uri.query || "")
    sdk_response(list_prs_body(repo))
  end

  defp response_for_get(_request, _uri, ["repos", owner, repo, "pulls", pull_number]) do
    repo = repo_name(owner, repo)
    pull_number = String.to_integer(pull_number)
    sdk_response(fetch_pr_body(repo, pull_number))
  end

  defp response_for_get(_request, uri, ["repos", owner, repo, "pulls", pull_number, "reviews"]) do
    repo = repo_name(owner, repo)
    pull_number = String.to_integer(pull_number)
    _params = URI.decode_query(uri.query || "")
    sdk_response(list_reviews_body(repo, pull_number))
  end

  defp response_for_get(_request, uri, ["repos", owner, repo, "pulls", pull_number, "comments"]) do
    repo = repo_name(owner, repo)
    pull_number = String.to_integer(pull_number)
    _params = URI.decode_query(uri.query || "")
    sdk_response(list_review_comments_body(repo, pull_number))
  end

  defp response_for_get(_request, uri, ["repos", owner, repo, "commits", ref, "check-runs"]) do
    repo = repo_name(owner, repo)
    _params = URI.decode_query(uri.query || "")
    sdk_response(check_runs_body(repo, ref))
  end

  defp response_for_get(_request, uri, ["repos", owner, repo, "commits", ref, "status"]) do
    repo = repo_name(owner, repo)
    _params = URI.decode_query(uri.query || "")
    sdk_response(combined_status_body(repo, ref))
  end

  defp response_for_get(_request, uri, ["repos", owner, repo, "commits", ref, "statuses"]) do
    repo = repo_name(owner, repo)
    _params = URI.decode_query(uri.query || "")
    sdk_response(commit_statuses_body(repo, ref))
  end

  defp response_for_get(_request, uri, ["repos", owner, repo, "commits"]) do
    repo = repo_name(owner, repo)
    params = URI.decode_query(uri.query || "")
    sha = Map.get(params, "sha", @base_ref)
    sdk_response(list_commits_body(repo, sha))
  end

  defp response_for_get(_request, _uri, ["repos", owner, repo, "issues", issue_number]) do
    repo = repo_name(owner, repo)
    issue_number = String.to_integer(issue_number)
    sdk_response(fetch_issue_body(repo, issue_number))
  end

  defp response_for_get(request, uri, _segments), do: missing_fixture_response(request, uri)

  defp response_for_post(request, _uri, ["repos", owner, repo, "issues"]) do
    repo = repo_name(owner, repo)
    body = decode_request_body(request)
    sdk_response(create_issue_body(repo, body))
  end

  defp response_for_post(request, _uri, ["repos", owner, repo, "pulls"]) do
    repo = repo_name(owner, repo)
    body = decode_request_body(request)
    sdk_response(create_pr_body(repo, body))
  end

  defp response_for_post(request, _uri, ["repos", owner, repo, "pulls", pull_number, "reviews"]) do
    repo = repo_name(owner, repo)
    pull_number = String.to_integer(pull_number)
    body = decode_request_body(request)
    sdk_response(create_review_body(repo, pull_number, body))
  end

  defp response_for_post(request, _uri, ["repos", owner, repo, "pulls", pull_number, "comments"]) do
    repo = repo_name(owner, repo)
    pull_number = String.to_integer(pull_number)
    body = decode_request_body(request)
    sdk_response(create_review_comment_body(repo, pull_number, body))
  end

  defp response_for_post(request, _uri, ["repos", owner, repo, "issues", issue_number, "labels"]) do
    repo = repo_name(owner, repo)
    issue_number = String.to_integer(issue_number)
    body = decode_request_body(request)
    sdk_response(label_issue_body(repo, issue_number, body))
  end

  defp response_for_post(
         request,
         _uri,
         ["repos", owner, repo, "issues", issue_number, "comments"]
       ) do
    repo = repo_name(owner, repo)
    issue_number = String.to_integer(issue_number)
    body = decode_request_body(request)
    sdk_response(create_comment_body(repo, issue_number, body))
  end

  defp response_for_post(request, uri, _segments), do: missing_fixture_response(request, uri)

  defp response_for_patch(request, _uri, ["repos", owner, repo, "issues", issue_number]) do
    repo = repo_name(owner, repo)
    issue_number = String.to_integer(issue_number)
    body = decode_request_body(request)
    sdk_response(update_issue_body(repo, issue_number, body))
  end

  defp response_for_patch(request, _uri, ["repos", owner, repo, "pulls", pull_number]) do
    repo = repo_name(owner, repo)
    pull_number = String.to_integer(pull_number)
    body = decode_request_body(request)
    sdk_response(update_pr_body(repo, pull_number, body))
  end

  defp response_for_patch(
         request,
         _uri,
         ["repos", owner, repo, "issues", "comments", comment_id]
       ) do
    repo = repo_name(owner, repo)
    comment_id = String.to_integer(comment_id)
    body = decode_request_body(request)
    sdk_response(update_comment_body(repo, comment_id, body))
  end

  defp response_for_patch(request, uri, _segments), do: missing_fixture_response(request, uri)

  defp missing_fixture_response(request, uri) do
    sdk_response(
      %{"message" => "missing github fixture for #{request.method} #{uri.path}"},
      404
    )
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

  defp create_pr_body(repo, body) do
    pr_body =
      pr_provider_body(repo, @pull_number, Map.get(body, "title"), Map.get(body, "body"), %{
        "head" => %{"ref" => Map.get(body, "head"), "sha" => @head_sha},
        "base" => %{"ref" => Map.get(body, "base"), "sha" => @base_sha},
        "draft" => Map.get(body, "draft", false)
      })

    Map.put(pr_body, "maintainer_can_modify", Map.get(body, "maintainer_can_modify", false))
  end

  defp list_prs_body(repo) do
    [fetch_pr_body(repo, @pull_number)]
  end

  defp fetch_pr_body(repo, pull_number) do
    pr_provider_body(
      repo,
      pull_number,
      "PR #{pull_number} in #{repo}",
      "Deterministic PR body",
      %{}
    )
  end

  defp update_pr_body(repo, pull_number, body) do
    pr_provider_body(repo, pull_number, Map.get(body, "title"), Map.get(body, "body"), %{
      "state" => Map.get(body, "state", "open"),
      "base" => %{"ref" => Map.get(body, "base", @base_ref), "sha" => @base_sha},
      "maintainer_can_modify" => Map.get(body, "maintainer_can_modify", false)
    })
  end

  defp list_reviews_body(repo, pull_number) do
    review_summaries(repo, pull_number)
    |> Enum.map(&review_provider_body/1)
  end

  defp list_review_comments_body(repo, pull_number) do
    review_comment_summaries(repo, pull_number)
    |> Enum.map(&review_comment_provider_body/1)
  end

  defp create_review_body(repo, pull_number, body) do
    repo
    |> created_review_summary(pull_number, Map.get(body, "body"), Map.get(body, "event"))
    |> review_provider_body()
  end

  defp create_review_comment_body(repo, pull_number, body) do
    repo
    |> created_review_comment_summary(
      pull_number,
      Map.get(body, "body"),
      Map.get(body, "commit_id"),
      Map.get(body, "path")
    )
    |> Map.merge(%{
      line: Map.get(body, "line"),
      side: Map.get(body, "side"),
      start_line: Map.get(body, "start_line"),
      start_side: Map.get(body, "start_side"),
      position: Map.get(body, "position")
    })
    |> review_comment_provider_body()
  end

  defp check_runs_body(repo, ref) do
    %{
      "total_count" => length(check_run_summaries(repo, ref)),
      "check_runs" => Enum.map(check_run_summaries(repo, ref), &check_run_provider_body/1)
    }
  end

  defp combined_status_body(repo, ref) do
    statuses = commit_status_summaries(repo, ref)

    %{
      "sha" => ref,
      "state" => "success",
      "total_count" => length(statuses),
      "statuses" => Enum.map(statuses, &status_provider_body/1)
    }
  end

  defp commit_statuses_body(repo, ref) do
    repo
    |> commit_status_summaries(ref)
    |> Enum.map(&status_provider_body/1)
  end

  defp list_commits_body(repo, sha) do
    repo
    |> commit_summaries(sha)
    |> Enum.map(&commit_provider_body/1)
  end

  defp pr_provider_body(repo, pull_number, title, body, overrides) do
    %{
      "number" => pull_number,
      "title" => title,
      "body" => body,
      "state" => Map.get(overrides, "state", "open"),
      "draft" => Map.get(overrides, "draft", false),
      "merged" => false,
      "mergeable" => true,
      "maintainer_can_modify" => Map.get(overrides, "maintainer_can_modify", false),
      "html_url" => "https://github.com/#{repo}/pull/#{pull_number}",
      "diff_url" => "https://github.com/#{repo}/pull/#{pull_number}.diff",
      "patch_url" => "https://github.com/#{repo}/pull/#{pull_number}.patch",
      "commits_url" => "https://api.github.com/repos/#{repo}/pulls/#{pull_number}/commits",
      "review_comments_url" =>
        "https://api.github.com/repos/#{repo}/pulls/#{pull_number}/comments",
      "head" =>
        ref_body(repo, Map.get(Map.get(overrides, "head", %{}), "ref", @head_ref), @head_sha),
      "base" =>
        ref_body(repo, Map.get(Map.get(overrides, "base", %{}), "ref", @base_ref), @base_sha),
      "user" => %{"login" => @subject},
      "labels" => [%{"name" => "platform"}, %{"name" => "parity"}],
      "requested_reviewers" => [%{"login" => "reviewer"}]
    }
  end

  defp ref_body(repo, ref, sha) do
    %{"ref" => ref, "sha" => sha, "repo" => %{"full_name" => repo}}
  end

  defp pr_summary(repo, pull_number, title, body, overrides) do
    pr_provider_body(repo, pull_number, title, body, overrides)
    |> normalize_fixture_pr(repo)
  end

  defp normalize_fixture_pr(body, repo) do
    %{
      repo: repo,
      pull_number: Map.get(body, "number"),
      title: Map.get(body, "title"),
      body: Map.get(body, "body"),
      state: Map.get(body, "state"),
      draft: Map.get(body, "draft"),
      merged: Map.get(body, "merged"),
      mergeable: Map.get(body, "mergeable"),
      maintainer_can_modify: Map.get(body, "maintainer_can_modify"),
      html_url: Map.get(body, "html_url"),
      diff_url: Map.get(body, "diff_url"),
      patch_url: Map.get(body, "patch_url"),
      commits_url: Map.get(body, "commits_url"),
      review_comments_url: Map.get(body, "review_comments_url"),
      head: ref_summary(Map.get(body, "head")),
      base: ref_summary(Map.get(body, "base")),
      user: @subject,
      labels: normalize_fixture_labels(Map.get(body, "labels", [])),
      requested_reviewers: normalize_fixture_logins(Map.get(body, "requested_reviewers", []))
    }
  end

  defp ref_summary(%{"ref" => ref, "sha" => sha, "repo" => %{"full_name" => repo}}) do
    %{ref: ref, sha: sha, repo: repo}
  end

  defp review_summaries(repo, pull_number) do
    [
      %{
        review_id: review_seed(repo, pull_number, "COMMENT"),
        state: "COMMENTED",
        body: "Review note for #{repo}##{pull_number}",
        commit_id: @head_sha,
        submitted_at: "2026-03-12T00:01:00Z",
        user: @subject,
        html_url: "https://github.com/#{repo}/pull/#{pull_number}#pullrequestreview-1"
      },
      %{
        review_id: review_seed(repo, pull_number, "APPROVE"),
        state: "APPROVED",
        body: "Looks good",
        commit_id: @head_sha,
        submitted_at: "2026-03-12T00:02:00Z",
        user: "reviewer",
        html_url: "https://github.com/#{repo}/pull/#{pull_number}#pullrequestreview-2"
      }
    ]
  end

  defp created_review_summary(repo, pull_number, body, event) do
    %{
      review_id: review_seed(repo, pull_number, event),
      state: review_state(event),
      body: body,
      commit_id: @head_sha,
      submitted_at: "2026-03-12T00:03:00Z",
      user: @subject,
      html_url: "https://github.com/#{repo}/pull/#{pull_number}#pullrequestreview-created"
    }
  end

  defp review_provider_body(summary) do
    %{
      "id" => summary.review_id,
      "state" => summary.state,
      "body" => summary.body,
      "commit_id" => summary.commit_id,
      "submitted_at" => summary.submitted_at,
      "user" => %{"login" => summary.user},
      "html_url" => summary.html_url
    }
  end

  defp review_comment_summaries(repo, pull_number) do
    [
      %{
        comment_id: review_comment_seed(repo, pull_number, "first"),
        body: "Inline note one",
        path: "lib/source.ex",
        diff_hunk: "@@ -10,6 +10,7 @@",
        position: 4,
        line: 12,
        side: "RIGHT",
        start_line: nil,
        start_side: nil,
        commit_id: @head_sha,
        original_commit_id: @head_sha,
        in_reply_to_id: nil,
        pull_request_review_id: review_seed(repo, pull_number, "COMMENT"),
        user: @subject,
        html_url: "https://github.com/#{repo}/pull/#{pull_number}#discussion_r1"
      },
      %{
        comment_id: review_comment_seed(repo, pull_number, "reply"),
        body: "Inline note reply",
        path: "lib/source.ex",
        diff_hunk: "@@ -10,6 +10,7 @@",
        position: 5,
        line: 13,
        side: "RIGHT",
        start_line: nil,
        start_side: nil,
        commit_id: @head_sha,
        original_commit_id: @head_sha,
        in_reply_to_id: review_comment_seed(repo, pull_number, "first"),
        pull_request_review_id: review_seed(repo, pull_number, "COMMENT"),
        user: "reviewer",
        html_url: "https://github.com/#{repo}/pull/#{pull_number}#discussion_r2"
      }
    ]
  end

  defp created_review_comment_summary(repo, pull_number, body, commit_id, path) do
    %{
      comment_id: review_comment_seed(repo, pull_number, body),
      body: body,
      path: path,
      diff_hunk: "@@ -10,6 +10,7 @@",
      position: nil,
      line: 12,
      side: "RIGHT",
      start_line: nil,
      start_side: nil,
      commit_id: commit_id,
      original_commit_id: commit_id,
      in_reply_to_id: nil,
      pull_request_review_id: review_seed(repo, pull_number, "COMMENT"),
      user: @subject,
      html_url: "https://github.com/#{repo}/pull/#{pull_number}#discussion_created"
    }
  end

  defp review_comment_provider_body(summary) do
    %{
      "id" => summary.comment_id,
      "body" => summary.body,
      "path" => summary.path,
      "diff_hunk" => summary.diff_hunk,
      "position" => summary.position,
      "line" => summary.line,
      "side" => summary.side,
      "start_line" => summary.start_line,
      "start_side" => summary.start_side,
      "commit_id" => summary.commit_id,
      "original_commit_id" => summary.original_commit_id,
      "in_reply_to_id" => summary.in_reply_to_id,
      "pull_request_review_id" => summary.pull_request_review_id,
      "user" => %{"login" => summary.user},
      "html_url" => summary.html_url
    }
  end

  defp check_run_summaries(repo, ref) do
    [
      %{
        check_run_id: check_run_seed(repo, ref, "ci"),
        name: "ci",
        head_sha: ref,
        status: "completed",
        conclusion: "success",
        html_url: "https://github.com/#{repo}/actions/runs/1/job/1",
        details_url: "https://github.com/#{repo}/actions/runs/1",
        started_at: "2026-03-12T00:00:00Z",
        completed_at: "2026-03-12T00:05:00Z",
        app_slug: "github-actions"
      },
      %{
        check_run_id: check_run_seed(repo, ref, "dialyzer"),
        name: "dialyzer",
        head_sha: ref,
        status: "completed",
        conclusion: "success",
        html_url: "https://github.com/#{repo}/actions/runs/1/job/2",
        details_url: "https://github.com/#{repo}/actions/runs/1",
        started_at: "2026-03-12T00:00:00Z",
        completed_at: "2026-03-12T00:06:00Z",
        app_slug: "github-actions"
      }
    ]
  end

  defp check_run_provider_body(summary) do
    %{
      "id" => summary.check_run_id,
      "name" => summary.name,
      "head_sha" => summary.head_sha,
      "status" => summary.status,
      "conclusion" => summary.conclusion,
      "html_url" => summary.html_url,
      "details_url" => summary.details_url,
      "started_at" => summary.started_at,
      "completed_at" => summary.completed_at,
      "app" => %{"slug" => summary.app_slug}
    }
  end

  defp commit_status_summaries(repo, ref) do
    [
      %{
        status_id: status_seed(repo, ref, "ci"),
        state: "success",
        context: "ci",
        description: "CI passed",
        target_url: "https://github.com/#{repo}/actions/runs/1",
        created_at: "2026-03-12T00:00:00Z",
        updated_at: "2026-03-12T00:05:00Z"
      },
      %{
        status_id: status_seed(repo, ref, "lint"),
        state: "success",
        context: "lint",
        description: "Lint passed",
        target_url: "https://github.com/#{repo}/actions/runs/2",
        created_at: "2026-03-12T00:00:00Z",
        updated_at: "2026-03-12T00:04:00Z"
      }
    ]
  end

  defp status_provider_body(summary) do
    %{
      "id" => summary.status_id,
      "state" => summary.state,
      "context" => summary.context,
      "description" => summary.description,
      "target_url" => summary.target_url,
      "created_at" => summary.created_at,
      "updated_at" => summary.updated_at
    }
  end

  defp commit_summaries(repo, sha) do
    [
      %{
        sha: @head_sha,
        html_url: "https://github.com/#{repo}/commit/#{@head_sha}",
        message: "Implement source backed workflow",
        author_name: "Octo Cat",
        author_email: "octo@example.com",
        author_date: "2026-03-12T00:00:00Z",
        committer_name: "Octo Cat",
        committer_email: "octo@example.com",
        committer_date: "2026-03-12T00:01:00Z"
      },
      %{
        sha: commit_seed(repo, sha),
        html_url: "https://github.com/#{repo}/commit/#{commit_seed(repo, sha)}",
        message: "Add deterministic fixtures",
        author_name: "Review Bot",
        author_email: "review@example.com",
        author_date: "2026-03-12T00:02:00Z",
        committer_name: "Review Bot",
        committer_email: "review@example.com",
        committer_date: "2026-03-12T00:03:00Z"
      }
    ]
  end

  defp commit_provider_body(summary) do
    %{
      "sha" => summary.sha,
      "html_url" => summary.html_url,
      "commit" => %{
        "message" => summary.message,
        "author" => %{
          "name" => summary.author_name,
          "email" => summary.author_email,
          "date" => summary.author_date
        },
        "committer" => %{
          "name" => summary.committer_name,
          "email" => summary.committer_email,
          "date" => summary.committer_date
        }
      }
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

  defp review_seed(repo, pull_number, event) do
    :erlang.phash2({repo, pull_number, event}, 1_000_000)
  end

  defp review_comment_seed(repo, pull_number, body) do
    :erlang.phash2({repo, pull_number, body}, 1_000_000)
  end

  defp check_run_seed(repo, ref, name) do
    :erlang.phash2({repo, ref, name}, 1_000_000)
  end

  defp status_seed(repo, ref, context) do
    :erlang.phash2({repo, ref, context}, 1_000_000)
  end

  defp commit_seed(repo, sha) do
    :crypto.hash(:sha, "#{repo}:#{sha}")
    |> Base.encode16(case: :lower)
    |> binary_part(0, 40)
  end

  defp issue_state(issue_number) when rem(issue_number, 2) == 0, do: "open"
  defp issue_state(_issue_number), do: "closed"

  defp label_set(issue_number) when rem(issue_number, 2) == 0, do: ["bug", "triaged"]
  defp label_set(_issue_number), do: ["enhancement"]

  defp review_state("APPROVE"), do: "APPROVED"
  defp review_state("REQUEST_CHANGES"), do: "CHANGES_REQUESTED"
  defp review_state(_event), do: "COMMENTED"

  defp normalize_fixture_labels(labels) when is_list(labels) do
    Enum.map(labels, fn
      %{"name" => name} -> name
      label when is_binary(label) -> label
    end)
  end

  defp normalize_fixture_logins(logins) when is_list(logins) do
    Enum.map(logins, fn
      %{"login" => login} -> login
      login when is_binary(login) -> login
    end)
  end

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
