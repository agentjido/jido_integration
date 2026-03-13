defmodule Jido.Integration.V2.StoreLocal.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Jido.Integration.V2.StoreLocal.Server
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
