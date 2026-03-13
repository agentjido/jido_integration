defmodule Jido.Integration.V2.Connectors.GitHub.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_github,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 GitHub Connector",
      description: "Example direct connector package for the greenfield platform"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jido_action, path: "../../../../../../jido_action"},
      {:jido_integration_v2_contracts, path: "../../core/contracts"},
      {:jido_integration_v2_direct_runtime, path: "../../core/direct_runtime"},
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_deps: :apps_direct,
      plt_add_apps: [:mix]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
