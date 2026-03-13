defmodule Jido.Integration.V2.Connectors.GitHub.Client.HTTP do
  @moduledoc false

  @behaviour Jido.Integration.V2.Connectors.GitHub.Client

  @default_base_url "https://api.github.com"
  @default_timeout 15_000
  @user_agent "jido-integration-v2-github/0.1.0"

  @impl true
  def list_issues(access_token, params, opts) do
    query =
      URI.encode_query(%{
        state: Map.get(params, :state, "open"),
        per_page: Map.get(params, :per_page, 30),
        page: Map.get(params, :page, 1)
      })

    request(:get, issue_path(params.repo) <> "?" <> query, access_token, nil, opts)
  end

  @impl true
  def fetch_issue(access_token, params, opts) do
    request(:get, "#{issue_path(params.repo)}/#{params.issue_number}", access_token, nil, opts)
  end

  @impl true
  def create_issue(access_token, params, opts) do
    request(
      :post,
      issue_path(params.repo),
      access_token,
      %{
        title: params.title,
        body: Map.get(params, :body),
        labels: Map.get(params, :labels, []),
        assignees: Map.get(params, :assignees, [])
      },
      opts
    )
  end

  @impl true
  def update_issue(access_token, params, opts) do
    request(
      :patch,
      "#{issue_path(params.repo)}/#{params.issue_number}",
      access_token,
      %{
        title: Map.get(params, :title),
        body: Map.get(params, :body),
        state: Map.get(params, :state),
        labels: Map.get(params, :labels),
        assignees: Map.get(params, :assignees)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new(),
      opts
    )
  end

  @impl true
  def label_issue(access_token, params, opts) do
    request(
      :post,
      "#{issue_path(params.repo)}/#{params.issue_number}/labels",
      access_token,
      %{labels: Map.get(params, :labels, [])},
      opts
    )
  end

  @impl true
  def close_issue(access_token, params, opts) do
    request(
      :patch,
      "#{issue_path(params.repo)}/#{params.issue_number}",
      access_token,
      %{state: "closed"},
      opts
    )
  end

  @impl true
  def create_comment(access_token, params, opts) do
    request(
      :post,
      "#{issue_path(params.repo)}/#{params.issue_number}/comments",
      access_token,
      %{body: params.body},
      opts
    )
  end

  @impl true
  def update_comment(access_token, params, opts) do
    request(
      :patch,
      "#{repo_path(params.repo)}/issues/comments/#{params.comment_id}",
      access_token,
      %{body: params.body},
      opts
    )
  end

  defp request(method, path, access_token, body, opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    url = String.to_charlist(base_url <> path)

    headers = headers(access_token, body != nil)

    request =
      case body do
        nil ->
          {url, headers}

        payload ->
          {url, headers, ~c"application/json", Jason.encode!(payload)}
      end

    options = [timeout: timeout, connect_timeout: timeout]

    case :httpc.request(method, request, options, body_format: :binary) do
      {:ok, {{_http_version, status, _reason}, _headers, response_body}}
      when status in 200..299 ->
        {:ok, decode_body(response_body)}

      {:ok, {{_http_version, status, _reason}, _headers, response_body}} ->
        {:error, {:http_error, status, decode_body(response_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp headers(access_token, include_content_type?) do
    base_headers = [
      {~c"accept", ~c"application/vnd.github+json"},
      {~c"authorization", String.to_charlist("Bearer " <> access_token)},
      {~c"x-github-api-version", ~c"2022-11-28"},
      {~c"user-agent", String.to_charlist(@user_agent)}
    ]

    if include_content_type? do
      [{~c"content-type", ~c"application/json"} | base_headers]
    else
      base_headers
    end
  end

  defp issue_path(repo), do: repo_path(repo) <> "/issues"

  defp repo_path(repo) do
    case String.split(repo, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        "/repos/#{owner}/#{name}"

      _other ->
        raise ArgumentError, "repo must be in owner/name format, got: #{inspect(repo)}"
    end
  end

  defp decode_body(""), do: %{}
  defp decode_body(body), do: Jason.decode!(body)
end
