defmodule Jido.Integration.V2.Conformance.Renderer do
  @moduledoc false

  alias Jido.Integration.V2.Conformance.Report

  @type format :: :human | :json

  @spec formats() :: [format()]
  def formats, do: [:human, :json]

  @spec render(Report.t(), format()) :: String.t()
  def render(%Report{} = report, :json) do
    report
    |> Report.to_map()
    |> Jason.encode!(pretty: true)
  end

  def render(%Report{} = report, :human) do
    [
      "Connector: #{report.connector_id}",
      "Module: #{inspect(report.connector_module)}",
      "Profile: #{report.profile}",
      "Status: #{status_label(report.status)}",
      "Runner: #{report.runner_version}",
      "Generated At: #{DateTime.to_iso8601(report.generated_at)}",
      "",
      Enum.map(report.suite_results, &render_suite/1)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp render_suite(suite) do
    summary =
      case suite.summary do
        nil -> ""
        value -> " - #{value}"
      end

    failures =
      suite.checks
      |> Enum.filter(&(&1.status == :failed))
      |> Enum.map(fn check -> "  x #{check.id}: #{check.message}" end)

    ["[#{status_label(suite.status)}] #{suite.id}#{summary}" | failures]
  end

  defp status_label(:passed), do: "PASS"
  defp status_label(:failed), do: "FAIL"
  defp status_label(:skipped), do: "SKIP"
end
