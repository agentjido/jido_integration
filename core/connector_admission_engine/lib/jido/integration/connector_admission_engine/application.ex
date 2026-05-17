defmodule Jido.Integration.ConnectorAdmissionEngine.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Jido.Integration.ConnectorAdmissionEngine.Store
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: Jido.Integration.ConnectorAdmissionEngine.Supervisor
    )
  end
end
