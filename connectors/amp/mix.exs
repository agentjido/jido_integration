unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

defmodule Jido.Integration.V2.Connectors.Amp.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_v2_amp,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Amp Connector",
      description: "Amp CLI connector lane for governed provider execution"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:jido, "~> 2.2"},
      {:jido_action, "~> 2.2"},
      {:zoi, "~> 0.17"},
      DependencyResolver.jido_integration_contracts(override: true),
      DependencyResolver.jido_integration_v2_consumer_surfaces(override: true),
      DependencyResolver.jido_integration_v2_direct_runtime(override: true),
      DependencyResolver.jido_integration_v2_connector_registry(override: true),
      DependencyResolver.jido_integration_v2_tool_contracts(override: true),
      DependencyResolver.amp_sdk(override: true),
      DependencyResolver.cli_subprocess_core(override: true),
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [plt_add_deps: :apps_direct]
  end

  defp docs do
    [main: "readme", extras: ["README.md"]]
  end
end
