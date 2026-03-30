defmodule Jido.BoundaryBridge.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_boundary_bridge,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Boundary Bridge",
      description: "Lower-boundary sandbox bridge package for external runtime kernels"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:zoi, "~> 0.17"},
      {:splode, "~> 0.3.0"},
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
      extras: [
        "README.md",
        "../../guides/architecture.md",
        "../../guides/runtime_model.md",
        "../../guides/publishing.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: [
          "../../guides/architecture.md",
          "../../guides/runtime_model.md",
          "../../guides/publishing.md"
        ]
      ]
    ]
  end
end
