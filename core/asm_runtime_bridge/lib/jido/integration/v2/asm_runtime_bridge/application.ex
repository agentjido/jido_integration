defmodule Jido.Integration.V2.AsmRuntimeBridge.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Jido.Integration.V2.AsmRuntimeBridge.SessionStore, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__.Supervisor)
  end
end
