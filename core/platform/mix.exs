unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

defmodule Jido.Integration.V2.Platform.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_v2,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Platform",
      description: "Public facade package for the Jido Integration platform"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      DependencyResolver.jido_integration_v2_contracts(),
      DependencyResolver.jido_integration_v2_auth(),
      DependencyResolver.jido_integration_v2_brain_ingress(),
      DependencyResolver.jido_integration_v2_control_plane(),
      DependencyResolver.jido_integration_v2_runtime_router(only: :test),
      DependencyResolver.jido_integration_v2_store_postgres(only: :test),
      DependencyResolver.jido_integration_v2_github(only: :test),
      DependencyResolver.jido_integration_v2_codex_cli(only: :test),
      DependencyResolver.jido_integration_v2_market_data(only: :test),
      DependencyResolver.req_llm(),
      DependencyResolver.splode(),
      {:plug, "~> 1.19", only: [:dev, :test]},
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
        "guides/inference_review_packets.md",
        {"examples/README.md", filename: "examples_readme"},
        "../../guides/inference_baseline.md",
        "../../guides/architecture.md",
        "../../guides/runtime_model.md",
        "../../guides/connector_lifecycle.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Inference: [
          "guides/inference_review_packets.md",
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
