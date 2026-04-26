defmodule Jido.Integration.V2.Connectors.GitHub.Conformance do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.GitHub.Fixtures
  alias Jido.Integration.V2.Connectors.GitHub.OperationCatalog

  @repo "acme/platform"
  @subject "octo-user"
  @access_token "gho-demo-conformance"
  @run_id "run-github-conformance"
  @attempt_id "#{@run_id}:1"

  @spec fixtures() :: [map()]
  def fixtures do
    Enum.map(Fixtures.published_capability_ids(), fn capability_id ->
      entry = OperationCatalog.fetch!(capability_id)
      input = conformance_input(capability_id)

      %{
        capability_id: capability_id,
        input: input,
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{
          run_id: @run_id,
          attempt_id: @attempt_id,
          opts: %{github_client: Fixtures.client_opts(nil)}
        },
        expect: %{
          output: Fixtures.expected_output(capability_id, input, @subject, @access_token),
          event_types: ["attempt.started", entry.event_type, "attempt.completed"],
          artifact_types: [:tool_output],
          artifact_keys: ["github/#{@run_id}/#{@attempt_id}/#{entry.artifact_slug}.term"]
        }
      }
    end)
  end

  defp credential_ref do
    %{
      id: "cred-github-conformance",
      profile_id: "personal_access_token",
      subject: @subject,
      scopes: ["repo"],
      lease_fields: ["access_token"]
    }
  end

  defp credential_lease do
    %{
      lease_id: "lease-github-conformance",
      credential_ref_id: "cred-github-conformance",
      profile_id: "personal_access_token",
      subject: @subject,
      scopes: ["repo"],
      payload: %{access_token: @access_token},
      lease_fields: ["access_token"],
      issued_at: ~U[2026-03-12 00:00:00Z],
      expires_at: ~U[2026-03-12 00:05:00Z]
    }
  end

  defp conformance_input("github.issue.list"),
    do: %{repo: @repo, state: "open", per_page: 2, page: 1}

  defp conformance_input("github.check_runs.list_for_ref"),
    do: %{
      repo: @repo,
      ref: "f00dbabe1234567890abcdef1234567890abcdef",
      status: "completed",
      per_page: 2,
      page: 1
    }

  defp conformance_input("github.commit.statuses.get_combined"),
    do: %{repo: @repo, ref: "f00dbabe1234567890abcdef1234567890abcdef", per_page: 2, page: 1}

  defp conformance_input("github.commit.statuses.list"),
    do: %{repo: @repo, ref: "f00dbabe1234567890abcdef1234567890abcdef", per_page: 2, page: 1}

  defp conformance_input("github.commits.list"),
    do: %{repo: @repo, sha: "main", path: "lib", per_page: 2, page: 1}

  defp conformance_input("github.contents.upsert") do
    %{
      repo: @repo,
      path: "generated/live-e2e/jido-conformance-proof.txt",
      message: "Add conformance scratch artifact",
      content: "scratch artifact",
      branch: "jido-conformance-proof"
    }
  end

  defp conformance_input("github.git.ref.create") do
    %{
      repo: @repo,
      ref: "refs/heads/jido-conformance-proof",
      sha: "0ddba11adeadbeef1234567890abcdef12345678"
    }
  end

  defp conformance_input("github.git.ref.delete"),
    do: %{repo: @repo, ref: "heads/jido-conformance-proof"}

  defp conformance_input("github.issue.fetch"),
    do: %{repo: @repo, issue_number: 77}

  defp conformance_input("github.issue.create") do
    %{repo: @repo, title: "Conformance review", body: "Generated from deterministic fixture"}
  end

  defp conformance_input("github.issue.update") do
    %{
      repo: @repo,
      issue_number: 77,
      title: "Conformance review updated",
      body: "Expanded deterministic coverage",
      state: "open",
      labels: ["platform", "v2"],
      assignees: ["octo-user"]
    }
  end

  defp conformance_input("github.issue.label"),
    do: %{repo: @repo, issue_number: 77, labels: ["platform", "triaged"]}

  defp conformance_input("github.issue.close"),
    do: %{repo: @repo, issue_number: 77}

  defp conformance_input("github.comment.create"),
    do: %{repo: @repo, issue_number: 77, body: "Generated comment"}

  defp conformance_input("github.comment.update"),
    do: %{repo: @repo, comment_id: 901, body: "Updated comment"}

  defp conformance_input("github.pr.create") do
    %{
      repo: @repo,
      title: "Source-backed GitHub connector parity",
      body: "Open PR through the governed direct runtime",
      head: "source-backed-work",
      base: "main",
      draft: true
    }
  end

  defp conformance_input("github.pr.fetch"),
    do: %{repo: @repo, pull_number: 17}

  defp conformance_input("github.pr.list"),
    do: %{repo: @repo, state: "all", per_page: 2, page: 1}

  defp conformance_input("github.pr.update") do
    %{
      repo: @repo,
      pull_number: 17,
      title: "Source-backed GitHub connector parity updated",
      body: "Updated through the governed direct runtime",
      state: "open",
      base: "main",
      maintainer_can_modify: true
    }
  end

  defp conformance_input("github.pr.reviews.list"),
    do: %{repo: @repo, pull_number: 17, per_page: 2, page: 1}

  defp conformance_input("github.pr.review_comments.list") do
    %{
      repo: @repo,
      pull_number: 17,
      sort: "created",
      direction: "asc",
      per_page: 2,
      page: 1
    }
  end

  defp conformance_input("github.pr.review.create") do
    %{repo: @repo, pull_number: 17, body: "Connector parity review", event: "COMMENT"}
  end

  defp conformance_input("github.pr.review_comment.create") do
    %{
      repo: @repo,
      pull_number: 17,
      body: "Inline connector parity note",
      commit_id: "f00dbabe1234567890abcdef1234567890abcdef",
      path: "lib/source.ex",
      line: 12,
      side: "RIGHT"
    }
  end

  defp conformance_input("github.repo.fetch"),
    do: %{repo: @repo}
end
