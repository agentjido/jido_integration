defmodule Jido.Integration.V2.Conformance.Report do
  @moduledoc """
  Structured result returned by the conformance runner.
  """

  alias Jido.Integration.V2.Conformance.CheckResult
  alias Jido.Integration.V2.Conformance.SuiteResult

  @type status :: :passed | :failed

  @enforce_keys [
    :connector_module,
    :connector_id,
    :profile,
    :runner_version,
    :generated_at,
    :status,
    :suite_results
  ]
  defstruct [
    :connector_module,
    :connector_id,
    :profile,
    :runner_version,
    :generated_at,
    :status,
    suite_results: []
  ]

  @type t :: %__MODULE__{
          connector_module: module(),
          connector_id: String.t(),
          profile: atom(),
          runner_version: String.t(),
          generated_at: DateTime.t(),
          status: status(),
          suite_results: [SuiteResult.t()]
        }

  @spec passed?(t()) :: boolean()
  def passed?(%__MODULE__{status: :passed}), do: true
  def passed?(%__MODULE__{}), do: false

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = report) do
    %{
      connector_module: inspect(report.connector_module),
      connector_id: report.connector_id,
      profile: Atom.to_string(report.profile),
      runner_version: report.runner_version,
      generated_at: DateTime.to_iso8601(report.generated_at),
      status: Atom.to_string(report.status),
      suite_results: Enum.map(report.suite_results, &suite_to_map/1)
    }
  end

  defp suite_to_map(%SuiteResult{} = suite) do
    %{
      id: Atom.to_string(suite.id),
      status: Atom.to_string(suite.status),
      summary: suite.summary,
      checks: Enum.map(suite.checks, &check_to_map/1)
    }
  end

  defp check_to_map(%CheckResult{} = check) do
    %{
      id: check.id,
      status: Atom.to_string(check.status),
      message: check.message,
      details: normalize_value(check.details)
    }
  end

  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)

  defp normalize_value(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      {normalize_key(key), normalize_value(nested_value)}
    end)
  end

  defp normalize_value(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end
