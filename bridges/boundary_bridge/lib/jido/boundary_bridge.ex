defmodule Jido.BoundaryBridge do
  @moduledoc """
  Public package root for the lower-boundary sandbox bridge.
  """

  @doc """
  Returns the package role for this child package.
  """
  @spec role() :: :lower_boundary_bridge
  def role, do: :lower_boundary_bridge
end
