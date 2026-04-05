unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

defmodule Jido.Integration.V2.Apps.DevopsIncidentResponse.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_v2_devops_incident_response,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Devops Incident Response",
      description: "Async webhook proof app above the greenfield platform"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jido, "~> 2.2"},
      DependencyResolver.jido_integration_v2(),
      DependencyResolver.jido_integration_v2_auth(),
      DependencyResolver.jido_integration_v2_contracts(),
      DependencyResolver.jido_integration_v2_consumer_surfaces(),
      DependencyResolver.jido_integration_v2_ingress(),
      DependencyResolver.jido_integration_v2_dispatch_runtime(),
      DependencyResolver.jido_integration_v2_webhook_router(),
      DependencyResolver.jido_integration_v2_store_local(),
      {:zoi, "~> 0.17"},
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [plt_add_deps: :apps_direct]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
