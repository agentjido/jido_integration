defmodule DevopsIncidentResponse.GitHubIssueHandler do
  @moduledoc false

  @table :devops_incident_response_fail_once

  def handle_trigger(event, context) when is_map(event) do
    payload = value(event, :payload) || %{}
    body = value(payload, :body) || %{}
    issue = value(body, :issue) || %{}
    repository = value(body, :repository) || %{}
    repo = value(repository, :full_name) || "unknown/unknown"
    simulate = value(body, :simulate)

    case maybe_simulate_failure(simulate, value(event, :dedupe_key)) do
      :ok ->
        maybe_sleep(simulate)

        {:ok,
         %{
           "incident_key" => "#{repo}##{value(issue, :number)}",
           "summary" => value(issue, :title) || "Untitled issue",
           "action" => "page_oncall",
           "attempt" => context.attempt,
           "run_id" => context.run_id
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_simulate_failure("fail_once", dedupe_key) do
    key = {@table, dedupe_key}

    if :persistent_term.get(key, :ready) == :ready do
      :persistent_term.put(key, :failed)
      {:error, :incident_backend_timeout}
    else
      :ok
    end
  end

  defp maybe_simulate_failure("always_fail", _dedupe_key), do: {:error, :incident_backend_timeout}
  defp maybe_simulate_failure(_simulate, _dedupe_key), do: :ok

  defp maybe_sleep("slow"), do: Process.sleep(50)
  defp maybe_sleep(_simulate), do: :ok

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp value(_map, _key), do: nil
end
