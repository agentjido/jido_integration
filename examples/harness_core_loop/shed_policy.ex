defmodule Jido.Integration.Examples.HarnessCore.ShedPolicy do
  @moduledoc """
  Test policy that always sheds. Used to verify policy denial produces
  audit events in the harness core loop.
  """

  @behaviour Jido.Integration.Gateway.Policy

  @impl true
  def partition_key(envelope), do: Map.get(envelope, :connector_id, :default)

  @impl true
  def capacity(_partition), do: {:tokens, 0}

  @impl true
  def on_pressure(_partition, _pressure), do: :shed
end
