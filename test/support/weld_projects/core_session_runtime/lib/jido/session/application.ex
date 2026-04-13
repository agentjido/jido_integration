defmodule Jido.Session.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Jido.Session.Store
    ]

    opts = [strategy: :one_for_one, name: Jido.Session.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
