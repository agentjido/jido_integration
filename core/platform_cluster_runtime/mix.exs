defmodule PlatformClusterRuntime.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :jido_integration_v2_platform_cluster_runtime,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration Platform Cluster Runtime",
      description: "Canonical Horde registry and supervisor runtime for memory-path singletons"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:horde, "~> 0.10.0"},
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
      extras: ["README.md", "../../guides/runtime_model.md", "../../guides/architecture.md"],
      groups_for_extras: [
        Overview: ["README.md"],
        Runtime: ["../../guides/runtime_model.md", "../../guides/architecture.md"]
      ]
    ]
  end
end
