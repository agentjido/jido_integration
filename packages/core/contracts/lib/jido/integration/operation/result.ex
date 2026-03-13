defmodule Jido.Integration.Operation.Result do
  @moduledoc """
  Operation result — the standardized response wrapper for connector operations.
  """

  @type t :: %__MODULE__{
          status: :ok | :error,
          result: map(),
          meta: map()
        }

  defstruct status: :ok, result: %{}, meta: %{}

  @doc "Create a new result from an operation return value."
  @spec new(map()) :: t()
  def new(data) when is_map(data) do
    %__MODULE__{
      status: :ok,
      result: data,
      meta: %{
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end
end
