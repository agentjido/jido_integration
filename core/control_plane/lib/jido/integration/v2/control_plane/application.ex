defmodule Jido.Integration.V2.ControlPlane.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Jido.Integration.V2.ControlPlane.Persistence

  @test_build Mix.env() == :test

  @impl true
  def start(_type, _args) do
    children =
      [
        {Jido.Integration.V2.ControlPlane.Persistence.Owner, persistence_boot_attrs()},
        {Jido.Integration.V2.ControlPlane.RuntimeConfig, []},
        {Jido.Integration.V2.ControlPlane.Registry, []}
      ] ++
        test_store_children() ++
        [{Jido.Integration.V2.ControlPlane.AttemptReconciler, []}]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Jido.Integration.V2.ControlPlane.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp persistence_boot_attrs do
    if @test_build,
      do: [profile: :mickey_mouse, store_modules: Persistence.test_store_modules()],
      else: Application.fetch_env!(:jido_integration_v2_control_plane, :persistence)
  end

  defp test_store_children do
    if @test_build, do: [{Jido.Integration.V2.ControlPlane.RunLedger, []}], else: []
  end
end
