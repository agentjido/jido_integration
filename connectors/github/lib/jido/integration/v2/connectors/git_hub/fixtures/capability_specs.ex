defmodule Jido.Integration.V2.Connectors.GitHub.Fixtures.CapabilitySpecs do
  @moduledoc false

  @run_id "run-github-test"
  @attempt_id "#{@run_id}:1"
  @repo "agentjido/jido_integration_v2"
  @pull_number 17
  @head_ref "source-backed-work"
  @disposable_ref "refs/heads/jido-live-proof"
  @disposable_delete_ref "heads/jido-live-proof"
  @disposable_path "generated/live-e2e/jido-live-proof.txt"
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
      capability_id: "github.contents.upsert",
      event_type: "connector.github.contents.upserted",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/contents_upsert.term",
      input: %{
        repo: @repo,
        path: @disposable_path,
        message: "Add live E2E scratch artifact",
        content: "scratch artifact",
        branch: @head_ref
      }
    },
    %{
      capability_id: "github.git.ref.create",
      event_type: "connector.github.git.ref.created",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/git_ref_create.term",
      input: %{repo: @repo, ref: @disposable_ref, sha: @base_sha}
    },
    %{
      capability_id: "github.git.ref.delete",
      event_type: "connector.github.git.ref.deleted",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/git_ref_delete.term",
      input: %{repo: @repo, ref: @disposable_delete_ref}
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
    },
    %{
      capability_id: "github.repo.fetch",
      event_type: "connector.github.repo.fetched",
      artifact_key: "github/#{@run_id}/#{@attempt_id}/repo_fetch.term",
      input: %{repo: @repo}
    }
  ]

  @spec raw_specs() :: [map()]
  def raw_specs, do: @capability_specs

  @spec published_capability_ids() :: [String.t()]
  def published_capability_ids do
    Enum.map(@capability_specs, & &1.capability_id)
  end

  @spec input_for(String.t()) :: map()
  def input_for(capability_id) do
    @capability_specs
    |> Enum.find(&(&1.capability_id == capability_id))
    |> Map.fetch!(:input)
  end
end
