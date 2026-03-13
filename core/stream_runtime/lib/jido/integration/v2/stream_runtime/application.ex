defmodule Jido.Integration.V2.StreamRuntime.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Jido.Integration.V2.StreamRuntime.Store, []}
    ]

    opts = [strategy: :one_for_one, name: Jido.Integration.V2.StreamRuntime.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
