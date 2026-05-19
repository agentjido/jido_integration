defmodule Jido.Integration.V2.Connectors.GitHub.Fixtures.Responses do
  @moduledoc false

  alias Pristine.SDK.Response

  @subject "octocat"
  @access_token "gho_test"
  @pull_number 17
  @head_ref "source-backed-work"
  @base_ref "main"
  @head_sha "f00dbabe1234567890abcdef1234567890abcdef"
  @base_sha "0ddba11adeadbeef1234567890abcdef12345678"
  @content_sha "c0ffee1234567890abcdef1234567890abcdef12"

  @spec response_for_request(map(), map()) :: {:ok, Response.t()}
  def response_for_request(request, _context \\ %{}) do
    uri = URI.parse(request.url)
    segments = path_segments(uri.path)

    case request.method do
      :get -> response_for_get(request, uri, segments)
      :post -> response_for_post(request, uri, segments)
      :put -> response_for_put(request, uri, segments)
      :patch -> response_for_patch(request, uri, segments)
      :delete -> response_for_delete(request, uri, segments)
      _other -> missing_fixture_response(request, uri)
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

  defp response_for_get(_request, _uri, ["repos", owner, repo]) do
    repo = repo_name(owner, repo)
    sdk_response(repo_fetch_body(repo))
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

  defp response_for_post(request, _uri, ["repos", owner, repo, "git", "refs"]) do
    repo = repo_name(owner, repo)
    body = decode_request_body(request)
    sdk_response(create_ref_body(repo, body))
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

  defp response_for_put(request, _uri, ["repos", owner, repo, "contents" | path_segments]) do
    repo = repo_name(owner, repo)
    path = Enum.join(path_segments, "/")
    body = decode_request_body(request)
    sdk_response(upsert_contents_body(repo, path, body))
  end

  defp response_for_put(request, uri, _segments), do: missing_fixture_response(request, uri)

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

  defp response_for_delete(_request, _uri, ["repos", _owner, _repo, "git", "refs" | _ref]) do
    sdk_response(%{}, 204)
  end

  defp response_for_delete(request, uri, _segments), do: missing_fixture_response(request, uri)

  defp missing_fixture_response(request, uri) do
    sdk_response(
      %{"message" => "missing github fixture for #{request.method} #{uri.path}"},
      404
    )
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

  defp repo_fetch_body(repo) do
    %{
      "full_name" => repo,
      "default_branch" => @base_ref,
      "private" => false,
      "html_url" => "https://github.com/#{repo}"
    }
  end

  defp create_ref_body(repo, body) do
    sha = Map.get(body, "sha")

    %{
      "ref" => Map.get(body, "ref"),
      "node_id" => "REF_jido_live_proof",
      "object" => %{
        "type" => "commit",
        "sha" => sha,
        "url" => "https://api.github.com/repos/#{repo}/git/commits/#{sha}"
      }
    }
  end

  defp upsert_contents_body(repo, path, body) do
    branch = Map.get(body, "branch", @base_ref)

    %{
      "content" => %{
        "name" => Path.basename(path),
        "path" => path,
        "sha" => @content_sha,
        "html_url" => "https://github.com/#{repo}/blob/#{branch}/#{path}"
      },
      "commit" => %{
        "sha" => @head_sha,
        "html_url" => "https://github.com/#{repo}/commit/#{@head_sha}"
      }
    }
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
    check_runs = check_run_summaries(repo, ref)

    %{
      "total_count" => length(check_runs),
      "check_runs" => Enum.map(check_runs, &check_run_provider_body/1)
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
    |> Enum.map(&URI.decode/1)
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
end
