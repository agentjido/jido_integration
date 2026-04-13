defmodule Jido.Integration.V2.Conformance.CheckResult do
  @moduledoc """
  Result for one conformance check.
  """

  @type status :: :passed | :failed

  @enforce_keys [:id, :status]
  defstruct [:id, :status, :message, details: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          status: status(),
          message: String.t() | nil,
          details: map()
        }

  @spec pass(String.t() | atom(), String.t() | nil, map()) :: t()
  def pass(id, message \\ nil, details \\ %{}) do
    %__MODULE__{
      id: to_string(id),
      status: :passed,
      message: message,
      details: normalize_details(details)
    }
  end

  @spec fail(String.t() | atom(), String.t(), map()) :: t()
  def fail(id, message, details \\ %{}) do
    %__MODULE__{
      id: to_string(id),
      status: :failed,
      message: message,
      details: normalize_details(details)
    }
  end

  defp normalize_details(details) when is_map(details), do: details
  defp normalize_details(_details), do: %{}
end
