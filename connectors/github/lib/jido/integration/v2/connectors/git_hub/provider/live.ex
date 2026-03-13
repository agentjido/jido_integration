defmodule Jido.Integration.V2.Connectors.GitHub.Provider.Live do
  @moduledoc false

  @behaviour Jido.Integration.V2.Connectors.GitHub.Provider

  alias Jido.Integration.V2.Connectors.GitHub.Client.HTTP
  alias Jido.Integration.V2.Contracts

  @impl true
  def list_issues(params, context) do
    with {:ok, issues} <- client().list_issues(access_token(context), params, client_opts()) do
      {:ok,
       %{
         repo: params.repo,
         state: Map.get(params, :state, "open"),
         page: Map.get(params, :page, 1),
         per_page: Map.get(params, :per_page, 30),
         total_count: length(issues),
         issues:
           Enum.map(issues, fn issue ->
             %{
               repo: params.repo,
               issue_number: Map.get(issue, "number"),
               title: Map.get(issue, "title"),
               state: Map.get(issue, "state"),
               labels: normalize_labels(Map.get(issue, "labels", []))
             }
           end)
       }}
    end
  end

  @impl true
  def fetch_issue(params, context) do
    with {:ok, issue} <- client().fetch_issue(access_token(context), params, client_opts()) do
      {:ok, normalize_issue_detail(issue, params.repo)}
    end
  end

  @impl true
  def create_issue(params, context) do
    with {:ok, issue} <- client().create_issue(access_token(context), params, client_opts()) do
      {:ok,
       %{
         repo: params.repo,
         issue_number: Map.get(issue, "number"),
         title: Map.get(issue, "title", params.title),
         body: Map.get(issue, "body", Map.get(params, :body)),
         state: Map.get(issue, "state", "open"),
         labels: normalize_labels(Map.get(issue, "labels", Map.get(params, :labels, []))),
         assignees: normalize_logins(Map.get(issue, "assignees", Map.get(params, :assignees, [])))
       }}
    end
  end

  @impl true
  def update_issue(params, context) do
    with {:ok, issue} <- client().update_issue(access_token(context), params, client_opts()) do
      {:ok,
       %{
         repo: params.repo,
         issue_number: Map.get(issue, "number", params.issue_number),
         title: Map.get(issue, "title", Map.get(params, :title)),
         body: Map.get(issue, "body", Map.get(params, :body)),
         state: Map.get(issue, "state", Map.get(params, :state, "open")),
         labels: normalize_labels(Map.get(issue, "labels", Map.get(params, :labels, []))),
         assignees: normalize_logins(Map.get(issue, "assignees", Map.get(params, :assignees, [])))
       }}
    end
  end

  @impl true
  def label_issue(params, context) do
    with {:ok, labels} <- client().label_issue(access_token(context), params, client_opts()) do
      {:ok,
       %{
         repo: params.repo,
         issue_number: params.issue_number,
         labels: normalize_labels(labels)
       }}
    end
  end

  @impl true
  def close_issue(params, context) do
    with {:ok, issue} <- client().close_issue(access_token(context), params, client_opts()) do
      {:ok,
       %{
         repo: params.repo,
         issue_number: Map.get(issue, "number", params.issue_number),
         state: Map.get(issue, "state", "closed")
       }}
    end
  end

  @impl true
  def create_comment(params, context) do
    with {:ok, comment} <- client().create_comment(access_token(context), params, client_opts()) do
      {:ok,
       %{
         repo: params.repo,
         issue_number: params.issue_number,
         comment_id: Map.get(comment, "id"),
         body: Map.get(comment, "body", params.body)
       }}
    end
  end

  @impl true
  def update_comment(params, context) do
    with {:ok, comment} <- client().update_comment(access_token(context), params, client_opts()) do
      {:ok,
       %{
         repo: params.repo,
         comment_id: Map.get(comment, "id", params.comment_id),
         body: Map.get(comment, "body", params.body)
       }}
    end
  end

  defp access_token(context) do
    case Contracts.get(context.credential_lease.payload, :access_token) do
      nil -> raise ArgumentError, "missing credential lease field :access_token"
      value -> value
    end
  end

  defp client do
    :jido_integration_v2_github
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:client, HTTP)
  end

  defp client_opts do
    :jido_integration_v2_github
    |> Application.get_env(__MODULE__, [])
    |> Keyword.take([:base_url, :timeout])
  end

  defp normalize_issue_detail(issue, repo) do
    %{
      repo: repo,
      issue_number: Map.get(issue, "number"),
      title: Map.get(issue, "title"),
      body: Map.get(issue, "body"),
      state: Map.get(issue, "state"),
      labels: normalize_labels(Map.get(issue, "labels", []))
    }
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
end
