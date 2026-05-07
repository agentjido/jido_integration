defmodule Jido.Integration.Store.Null do
  @moduledoc """
  Descriptor for persistence surfaces that can be explicitly disabled.
  """

  @spec descriptor() :: map()
  def descriptor do
    %{
      id: :null,
      tier: :off,
      default?: false,
      durable?: false,
      restart_safe?: false,
      shared?: false
    }
  end
end
