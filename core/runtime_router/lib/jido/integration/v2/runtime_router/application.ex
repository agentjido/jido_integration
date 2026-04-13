defmodule Jido.Integration.V2.RuntimeRouter.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Jido.Integration.V2.RuntimeRouter.SessionStore, []}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Jido.Integration.V2.RuntimeRouter.Supervisor
    )
  end
end
