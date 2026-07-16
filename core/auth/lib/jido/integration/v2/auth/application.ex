defmodule Jido.Integration.V2.Auth.Application do
  @moduledoc false

  use Application

  alias Jido.Integration.V2.Auth.Persistence

  @test_build Mix.env() == :test

  @impl true
  def start(_type, _args) do
    children =
      [
        {Jido.Integration.V2.Auth.Persistence.Owner, persistence_boot_attrs()},
        {Jido.Integration.V2.Auth.RuntimeConfig, []},
        {Task.Supervisor, name: Jido.Integration.V2.Auth.MaterializationSupervisor}
      ] ++ test_store_children()

    opts = [strategy: :one_for_one, name: Jido.Integration.V2.Auth.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp persistence_boot_attrs do
    if @test_build,
      do: [profile: :mickey_mouse, store_modules: Persistence.test_store_modules()],
      else: Application.fetch_env!(:jido_integration_v2_auth, :persistence)
  end

  defp test_store_children do
    if @test_build, do: [{Jido.Integration.V2.Auth.Store, []}], else: []
  end
end
