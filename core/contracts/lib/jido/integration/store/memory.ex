defmodule Jido.Integration.Store.Memory do
  @moduledoc """
  Descriptor for the process-lifetime memory store class.
  """

  @spec descriptor() :: map()
  def descriptor do
    %{
      id: :memory,
      tier: :memory_ephemeral,
      default?: true,
      durable?: false,
      restart_safe?: false,
      shared?: false
    }
  end
end
