defmodule Jido.Integration.V2.Connectors.GitHub.Provider.Deterministic do
  @moduledoc false

  @behaviour Jido.Integration.V2.Connectors.GitHub.Provider

  @impl true
  def list_issues(params, _context) do
    repo = params.repo
    state = Map.get(params, :state, "open")
    per_page = max(Map.get(params, :per_page, 30), 0)
    page = max(Map.get(params, :page, 1), 1)

    issues =
      for offset <- 0..(per_page - 1), per_page > 0 do
        issue_number = issue_seed(repo, state, page, offset)

        %{
          repo: repo,
          issue_number: issue_number,
          title: "Deterministic #{state} issue #{issue_number}",
          state: state,
          labels: label_set(issue_number)
        }
      end

    {:ok,
     %{
       repo: repo,
       state: state,
       page: page,
       per_page: per_page,
       total_count: length(issues),
       issues: issues
     }}
  end

  @impl true
  def fetch_issue(params, _context) do
    issue_number = params.issue_number

    {:ok,
     %{
       repo: params.repo,
       issue_number: issue_number,
       title: "Issue #{issue_number} in #{params.repo}",
       body: "Deterministic issue payload for #{params.repo}##{issue_number}",
       state: issue_state(issue_number),
       labels: label_set(issue_number)
     }}
  end

  @impl true
  def create_issue(params, context) do
    issue_number =
      :erlang.phash2({params.repo, params.title, context.credential_lease.subject}, 10_000)

    {:ok,
     %{
       repo: params.repo,
       issue_number: issue_number,
       title: params.title,
       body: Map.get(params, :body),
       state: "open",
       labels: Map.get(params, :labels, []),
       assignees: Map.get(params, :assignees, [])
     }}
  end

  @impl true
  def update_issue(params, _context) do
    issue_number = params.issue_number

    {:ok,
     %{
       repo: params.repo,
       issue_number: issue_number,
       title: Map.get(params, :title, "Issue #{issue_number} in #{params.repo}"),
       body:
         Map.get(params, :body, "Deterministic issue payload for #{params.repo}##{issue_number}"),
       state: Map.get(params, :state, issue_state(issue_number)),
       labels: Map.get(params, :labels, label_set(issue_number)),
       assignees: Map.get(params, :assignees, [])
     }}
  end

  @impl true
  def label_issue(params, _context) do
    {:ok,
     %{
       repo: params.repo,
       issue_number: params.issue_number,
       labels: Map.get(params, :labels, [])
     }}
  end

  @impl true
  def close_issue(params, _context) do
    {:ok,
     %{
       repo: params.repo,
       issue_number: params.issue_number,
       state: "closed"
     }}
  end

  @impl true
  def create_comment(params, context) do
    comment_id =
      :erlang.phash2(
        {params.repo, params.issue_number, params.body, context.credential_lease.subject},
        100_000
      )

    {:ok,
     %{
       repo: params.repo,
       issue_number: params.issue_number,
       comment_id: comment_id,
       body: params.body
     }}
  end

  @impl true
  def update_comment(params, _context) do
    {:ok,
     %{
       repo: params.repo,
       comment_id: params.comment_id,
       body: params.body
     }}
  end

  defp issue_seed(repo, state, page, offset) do
    :erlang.phash2({repo, state, page, offset}, 90_000) + 1
  end

  defp issue_state(issue_number) when rem(issue_number, 2) == 0, do: "open"
  defp issue_state(_issue_number), do: "closed"

  defp label_set(issue_number) when rem(issue_number, 2) == 0, do: ["bug", "triaged"]
  defp label_set(_issue_number), do: ["enhancement"]
end
