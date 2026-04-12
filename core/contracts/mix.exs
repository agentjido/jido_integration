defmodule Jido.Integration.V2.Contracts.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_contracts,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Contracts",
      description: "Greenfield public contracts for runs, attempts, capabilities, and credentials"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:jido, "~> 2.2"},
      {:jido_action, "~> 2.2"},
      {:jido_signal, "~> 2.1"},
      {:jcs, "~> 0.2.0"},
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
      extras: [
        "README.md",
        "guides/inference_contracts.md",
        {"examples/README.md", filename: "examples_readme"},
        "../../guides/inference_baseline.md",
        "../../guides/architecture.md",
        "../../guides/runtime_model.md",
        "../../guides/connector_lifecycle.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Inference: [
          "guides/inference_contracts.md",
          "../../guides/inference_baseline.md"
        ],
        Examples: ["examples/README.md"],
        Guides: [
          "../../guides/architecture.md",
          "../../guides/runtime_model.md",
          "../../guides/connector_lifecycle.md"
        ]
      ]
    ]
  end
end
