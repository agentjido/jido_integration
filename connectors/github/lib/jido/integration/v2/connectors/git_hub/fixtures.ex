defmodule Jido.Integration.V2.Connectors.GitHub.Fixtures do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures.CapabilitySpecs
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures.RequestAssertions
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures.Responses
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef

  @run_id "run-github-test"
  @attempt_id "#{@run_id}:1"
  @subject "octocat"
  @credential_ref_id "cred-github-test"
  @lease_id "lease-github-test"
  @profile_id "personal_access_token"
  @access_token "gho_test"
  @pull_number 17
  @head_ref "source-backed-work"
  @base_ref "main"
  @head_sha "f00dbabe1234567890abcdef1234567890abcdef"
  @base_sha "0ddba11adeadbeef1234567890abcdef12345678"
  @content_sha "c0ffee1234567890abcdef1234567890abcdef12"

  @spec specs() :: [map()]
  def specs do
    Enum.map(CapabilitySpecs.raw_specs(), fn spec ->
      Map.put(
        spec,
        :output,
        expected_output(spec.capability_id, spec.input, @subject, @access_token)
      )
    end)
  end

  @spec published_capability_ids() :: [String.t()]
  def published_capability_ids do
    CapabilitySpecs.published_capability_ids()
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
      tenant_id: "tenant-github-fixture",
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
    CapabilitySpecs.input_for(capability_id)
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

  def expected_output("github.contents.upsert", input, subject, token) do
    %{
      repo: input.repo,
      path: input.path,
      branch: input.branch,
      content_sha: @content_sha,
      commit_sha: @head_sha,
      html_url: "https://github.com/#{input.repo}/blob/#{input.branch}/#{input.path}",
      committed_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.git.ref.create", input, subject, token) do
    %{
      repo: input.repo,
      ref: input.ref,
      sha: input.sha,
      object_type: "commit",
      url: "https://api.github.com/repos/#{input.repo}/git/commits/#{input.sha}",
      node_id: "REF_jido_live_proof",
      created_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  def expected_output("github.git.ref.delete", input, subject, token) do
    %{
      repo: input.repo,
      ref: input.ref,
      deleted?: true,
      deleted_by: subject,
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

  def expected_output("github.repo.fetch", input, subject, token) do
    %{
      repo: input.repo,
      default_branch: @base_ref,
      private?: false,
      html_url: "https://github.com/#{input.repo}",
      fetched_by: subject,
      auth_binding: auth_binding(token)
    }
  end

  @spec assert_request(String.t(), map()) :: true
  def assert_request(capability_id, request) do
    RequestAssertions.assert_request(capability_id, request, input_for(capability_id))
  end

  @spec response_for_request(map(), map()) :: {:ok, Pristine.SDK.Response.t()}
  def response_for_request(request, context \\ %{}) do
    Responses.response_for_request(request, context)
  end

  @spec not_found_response() :: (map(), map() -> {:ok, Pristine.SDK.Response.t()})
  def not_found_response do
    Responses.not_found_response()
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
end
