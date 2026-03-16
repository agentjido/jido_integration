defmodule Jido.Integration.V2.Connectors.Notion.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_notion,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Notion Connector",
      description: "Thin direct Notion connector package backed by notion_sdk"
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
      {:jido_action, "~> 2.1"},
      {:jido_integration_v2_contracts, path: "../../core/contracts"},
      {:jido_integration_v2_direct_runtime, path: "../../core/direct_runtime"},
      {:jido_integration_v2_conformance,
       path: "../../core/conformance", only: :test, runtime: false},
      {:jido_integration_v2, path: "../../core/platform", only: [:dev, :test]},
      {:pristine, "~> 0.1.0", runtime: false},
      {:notion_sdk, "~> 0.1.0"},
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
