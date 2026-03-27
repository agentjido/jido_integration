Code.require_file("build_support/dependency_resolver.exs", __DIR__)

defmodule Jido.Integration.V2.Connectors.GitHub.MixProject do
  use Mix.Project

  alias Jido.Integration.V2.Connectors.GitHub.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_v2_github,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 GitHub Connector",
      description: "Thin direct GitHub connector package backed by github_ex"
    ]
  end

  defp elixirc_paths(:test), do: ["lib"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:jido, "~> 2.1"},
      {:jido_action, "~> 2.1"},
      {:jido_integration_v2_contracts, path: "../../core/contracts"},
      {:jido_integration_v2_consumer_surfaces, path: "../../core/consumer_surfaces"},
      {:jido_integration_v2_direct_runtime, path: "../../core/direct_runtime"},
      {:jido_integration_v2_conformance,
       path: "../../core/conformance", only: :test, runtime: false},
      {:jido_integration_v2, path: "../../core/platform", only: [:dev, :test]},
      {:zoi, "~> 0.17"},
      DependencyResolver.pristine_runtime(runtime: false),
      DependencyResolver.github_ex(),
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_deps: :apps_direct,
      plt_add_apps: [:mix, :pristine]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "docs/live_acceptance.md"]
    ]
  end
end
