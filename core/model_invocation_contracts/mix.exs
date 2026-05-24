unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

defmodule Jido.ModelInvocationContracts.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_model_invocation_contracts,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Model Invocation Contracts",
      description: "Stable governed model invocation request, receipt, and stream fragment DTOs"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      DependencyResolver.jido_integration_contracts(),
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
        "../../guides/inference_baseline.md",
        "../../guides/runtime_model.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: [
          "../../guides/inference_baseline.md",
          "../../guides/runtime_model.md"
        ]
      ]
    ]
  end
end
