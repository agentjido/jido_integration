defmodule Jido.Integration.V2.StorePostgres.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Jido.Integration.V2.StorePostgres.Repo,
      Jido.Integration.V2.StorePostgres.SubmissionRetentionWorker
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: Jido.Integration.V2.StorePostgres.Supervisor
    )
  end
end
