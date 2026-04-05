unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

Code.require_file("build_support/dependency_resolver.exs", __DIR__)

defmodule Jido.Integration.V2.Connectors.Linear.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver, as: WorkspaceDependencyResolver

  alias Jido.Integration.V2.Connectors.Linear.Build.DependencyResolver,
    as: ConnectorDependencyResolver

  def project do
    [
      app: :jido_integration_v2_linear,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Linear Connector",
      description: "Thin direct Linear connector package backed by linear_sdk"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp elixirc_paths(:test), do: ["lib"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:jido, "~> 2.2"},
      {:jido_action, "~> 2.2"},
      WorkspaceDependencyResolver.jido_integration_v2_contracts(),
      WorkspaceDependencyResolver.jido_integration_v2_consumer_surfaces(),
      WorkspaceDependencyResolver.jido_integration_v2_direct_runtime(),
      WorkspaceDependencyResolver.jido_integration_v2_conformance(only: :test, runtime: false),
      WorkspaceDependencyResolver.jido_integration_v2(only: [:dev, :test]),
      {:zoi, "~> 0.17"},
      ConnectorDependencyResolver.linear_sdk(),
      ConnectorDependencyResolver.prismatic(override: true),
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_deps: :apps_direct,
      plt_add_apps: [:mix, :prismatic]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
