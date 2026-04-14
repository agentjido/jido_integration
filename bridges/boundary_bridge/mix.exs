unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

defmodule Jido.BoundaryBridge.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  @source_url "https://github.com/agentjido/jido_integration"

  def project do
    [
      app: :jido_integration_v2_boundary_bridge,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      docs: docs(),
      source_url: @source_url,
      name: "Jido Integration V2 Boundary Bridge",
      description:
        "Deprecated lower-boundary sandbox bridge package retained as legacy reference code"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      DependencyResolver.jido_action(override: true),
      DependencyResolver.jido_os(),
      DependencyResolver.jido_shell(override: true),
      DependencyResolver.sprites(override: true),
      DependencyResolver.cli_subprocess_core(override: true),
      DependencyResolver.external_runtime_transport(override: true),
      {:zoi, "~> 0.17"},
      {:splode, "~> 0.3.0"},
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer"
      ]
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
        "CHANGELOG.md",
        "usage-rules.md",
        "docs/contract.md",
        "../../guides/architecture.md",
        "../../guides/runtime_model.md",
        "../../guides/publishing.md"
      ],
      groups_for_extras: [
        Overview: ["README.md", "docs/contract.md"],
        Project: ["CHANGELOG.md", "usage-rules.md"],
        Guides: [
          "../../guides/architecture.md",
          "../../guides/runtime_model.md",
          "../../guides/publishing.md"
        ]
      ]
    ]
  end
end
