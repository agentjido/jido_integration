defmodule Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueHandler do
  @moduledoc false

  def run(%{trigger: trigger}, context) do
    payload = trigger.payload
    issue = Map.get(payload, "issue", %{})
    repository = Map.get(payload, "repository", %{})
    repo = Map.get(repository, "full_name", "unknown/unknown")
    issue_number = Map.get(issue, "number", "unknown")
    title = Map.get(issue, "title", "Untitled issue")

    sleep_ms = payload["sleep_ms"] || 0

    if sleep_ms > 0 do
      Process.sleep(sleep_ms)
    end

    fail_attempts = payload["fail_attempts"] || 0

    if context.attempt <= fail_attempts do
      {:error, :incident_backend_timeout}
    else
      {:ok,
       %{
         "incident_key" => "#{repo}##{issue_number}",
         "summary" => title,
         "action" => "page_oncall",
         "attempt" => context.attempt,
         "run_id" => context.run_id
       }}
    end
  end
end
