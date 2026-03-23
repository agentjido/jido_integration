defmodule Jido.Integration.V2.Connectors.MarketData.AlertTriggerHandler do
  @moduledoc """
  Minimal direct-runtime contract for the authored poll trigger capability.

  Real poll admission still flows through `core/ingress`; this handler only
  satisfies the direct runtime fit contract for the published trigger
  capability.
  """

  @spec run(map(), map()) :: {:ok, map()}
  def run(input, _context) when is_map(input) do
    {:ok, input}
  end
end
