defmodule Jido.Integration.Store.Local do
  @moduledoc """
  Descriptor for the restart-safe single-node local store class.
  """

  @spec descriptor() :: map()
  def descriptor do
    %{
      id: :local,
      tier: :local_restart_safe,
      default?: false,
      durable?: true,
      restart_safe?: true,
      shared?: false
    }
  end
end
