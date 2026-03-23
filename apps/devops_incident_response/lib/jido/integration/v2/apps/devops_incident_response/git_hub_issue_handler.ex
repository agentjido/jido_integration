defmodule Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueHandler do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.RuntimeResult

  def run(%{trigger: trigger}, context) do
    payload = trigger.payload
    issue = Map.get(payload, "issue", %{})
    repository = Map.get(payload, "repository", %{})
    repo = Map.get(repository, "full_name", "unknown/unknown")
    issue_number = Map.get(issue, "number", "unknown")
    title = Map.get(issue, "title", "Untitled issue")
    attempt = Map.get(context, :attempt, 1)

    sleep_ms = payload["sleep_ms"] || 0

    if sleep_ms > 0 do
      Process.sleep(sleep_ms)
    end

    fail_attempts = payload["fail_attempts"] || 0

    if attempt <= fail_attempts do
      {:error, :incident_backend_timeout}
    else
      output = %{
        "incident_key" => "#{repo}##{issue_number}",
        "summary" => title,
        "action" => "page_oncall",
        "attempt" => attempt,
        "run_id" => context.run_id
      }

      {:ok,
       RuntimeResult.new!(%{
         output: output,
         events: [
           %{
             type: "connector.devops_incident_response.github_issue_ingested",
             stream: :control,
             payload: %{
               incident_key: output["incident_key"],
               trigger_id: trigger.trigger_id,
               attempt: attempt
             }
           }
         ],
         artifacts: [
           ArtifactBuilder.build!(
             run_id: context.run_id,
             attempt_id: Map.get(context, :attempt_id, "#{context.run_id}:#{attempt}"),
             artifact_type: :log,
             key:
               "devops_incident_response/#{context.run_id}/#{Map.get(context, :attempt_id, "#{context.run_id}:#{attempt}")}/github_issue_ingest.term",
             content: %{
               trigger_id: trigger.trigger_id,
               payload: payload,
               output: output
             },
             metadata: %{
               connector: "github",
               trigger_id: trigger.trigger_id
             }
           )
         ]
       })}
    end
  end
end
