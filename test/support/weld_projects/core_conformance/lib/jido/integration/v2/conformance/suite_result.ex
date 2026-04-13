defmodule Jido.Integration.V2.Conformance.SuiteResult do
  @moduledoc """
  Result for one conformance suite within a report.
  """

  alias Jido.Integration.V2.Conformance.CheckResult
  alias Jido.Integration.V2.Conformance.Profile

  @type status :: :passed | :failed | :skipped

  @enforce_keys [:id, :status, :checks]
  defstruct [:id, :status, :summary, checks: []]

  @type t :: %__MODULE__{
          id: Profile.suite_id(),
          status: status(),
          summary: String.t() | nil,
          checks: [CheckResult.t()]
        }

  @spec from_checks(Profile.suite_id(), [CheckResult.t()], String.t() | nil) :: t()
  def from_checks(id, checks, summary \\ nil) when is_list(checks) do
    status =
      if Enum.all?(checks, &match?(%CheckResult{status: :passed}, &1)),
        do: :passed,
        else: :failed

    %__MODULE__{id: id, status: status, summary: summary, checks: checks}
  end

  @spec skip(Profile.suite_id(), String.t()) :: t()
  def skip(id, summary) do
    %__MODULE__{id: id, status: :skipped, summary: summary, checks: []}
  end
end
