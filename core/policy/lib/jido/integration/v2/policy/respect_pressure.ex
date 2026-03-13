defmodule Jido.Integration.V2.Policy.RespectPressure do
  @moduledoc """
  Translates host-supplied pressure snapshots into a shed-only admission verdict.

  Backoff remains an async runtime concern, so non-shed pressure hints are ignored here.
  """

  @behaviour Jido.Integration.V2.Policy.Rule

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.Gateway

  @impl true
  def evaluate(%Capability{}, %Credential{}, _input, %{gateway: %Gateway{} = gateway}) do
    case Contracts.get(gateway.metadata, :pressure) do
      pressure when is_map(pressure) ->
        pressure
        |> pressure_decision()
        |> then(&rule_result(&1, pressure))

      _other ->
        :ok
    end
  end

  defp pressure_decision(pressure) do
    pressure
    |> Contracts.get(:decision, Contracts.get(pressure, :action))
    |> normalize_decision()
  end

  defp normalize_decision(:shed), do: :shed
  defp normalize_decision(:admit), do: :admit
  defp normalize_decision(:backoff), do: :ignore

  defp normalize_decision(decision) when is_binary(decision) do
    case String.trim(String.downcase(decision)) do
      "shed" -> :shed
      "admit" -> :admit
      "backoff" -> :ignore
      _other -> :ignore
    end
  end

  defp normalize_decision(_decision), do: :ignore

  defp rule_result(:shed, pressure), do: {:shed, [pressure_reason(pressure)]}
  defp rule_result(:admit, _pressure), do: :ok
  defp rule_result(:ignore, _pressure), do: :ok

  defp pressure_reason(pressure) do
    case Contracts.get(pressure, :reason) do
      reason when is_binary(reason) ->
        trimmed = String.trim(reason)

        if byte_size(trimmed) > 0 do
          trimmed
        else
          "pressure shed requested"
        end

      _other ->
        "pressure shed requested"
    end
  end
end
