defmodule Jido.Integration.Gateway.Policy.Default do
  @moduledoc """
  Default gateway policy — always admits operations.
  """
  @behaviour Jido.Integration.Gateway.Policy

  @impl true
  def partition_key(_envelope), do: :default

  @impl true
  def capacity(_partition), do: {:tokens, :infinity}

  @impl true
  def on_pressure(_partition, _pressure), do: :admit
end
