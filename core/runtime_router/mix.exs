unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

defmodule Jido.Integration.V2.RuntimeRouter.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_v2_runtime_router,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Runtime Router",
      description: "Integration-owned router for session and stream runtime lanes"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Integration.V2.RuntimeRouter.Application, []}
    ]
  end

  defp deps do
    [
      DependencyResolver.jido_integration_contracts(),
      DependencyResolver.jido_integration_v2_asm_runtime_bridge(),
      DependencyResolver.jido_session(),
      DependencyResolver.jido_runtime_control(override: true),
      DependencyResolver.execution_plane(),
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
