defmodule Jido.Integration.Store.Postgres do
  @moduledoc """
  Descriptor for the shared Postgres store class.
  """

  @spec descriptor() :: map()
  def descriptor do
    %{
      id: :postgres,
      tier: :postgres_shared,
      default?: false,
      durable?: true,
      restart_safe?: true,
      shared?: true
    }
  end
end
