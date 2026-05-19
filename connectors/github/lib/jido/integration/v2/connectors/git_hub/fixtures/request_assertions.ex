defmodule Jido.Integration.V2.Connectors.GitHub.Fixtures.RequestAssertions do
  @moduledoc false

  @access_token "gho_test"
  @head_sha "f00dbabe1234567890abcdef1234567890abcdef"

  @spec assert_request(String.t(), map(), map()) :: true
  def assert_request(capability_id, request, input) do
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

  defp assert_capability_request("github.contents.upsert", request, uri, input) do
    expect_equal(request.method, :put, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/contents/generated%2Flive-e2e%2Fjido-live-proof.txt",
      "request path"
    )

    expect_equal(
      Jason.decode!(request.body),
      %{
        "branch" => input.branch,
        "content" => Base.encode64(input.content),
        "message" => input.message
      },
      "request body"
    )
  end

  defp assert_capability_request("github.git.ref.create", request, uri, input) do
    expect_equal(request.method, :post, "request method")
    expect_equal(uri.path, "/repos/agentjido/jido_integration_v2/git/refs", "request path")

    expect_equal(
      Jason.decode!(request.body),
      %{"ref" => input.ref, "sha" => input.sha},
      "request body"
    )
  end

  defp assert_capability_request("github.git.ref.delete", request, uri, _input) do
    expect_equal(request.method, :delete, "request method")

    expect_equal(
      uri.path,
      "/repos/agentjido/jido_integration_v2/git/refs/heads%2Fjido-live-proof",
      "request path"
    )
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

  defp assert_capability_request("github.repo.fetch", request, uri, _input) do
    expect_equal(request.method, :get, "request method")
    expect_equal(uri.path, "/repos/agentjido/jido_integration_v2", "request path")
  end

  defp expect_equal(actual, expected, _label) when actual == expected, do: :ok

  defp expect_equal(actual, expected, label) do
    raise """
    unexpected #{label}
    expected: #{inspect(expected)}
    actual: #{inspect(actual)}
    """
  end
end
