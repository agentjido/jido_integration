unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

defmodule Jido.RuntimeControl.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  @version "0.1.0"

  def project do
    [
      app: :jido_runtime_control,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Runtime Control",
      description: "Shared runtime-control facade, IR, and driver contract layer"
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
      {:zoi, "~> 0.17"},
      {:splode, "~> 0.3.0"},
      {:jason, "~> 1.4"},
      {:jido, "~> 2.2"},
      {:jido_action, "~> 2.2"},
      {:jido_signal, "~> 2.1"},
      DependencyResolver.jido_shell(override: true),
      DependencyResolver.sprites(override: true),
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [plt_add_deps: :apps_tree]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/execution_plane_alignment.md",
        "docs/telemetry.md",
        "docs/dependency_policy.md",
        "../../guides/runtime_model.md",
        "../../guides/architecture.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Runtime: [
          "../../guides/runtime_model.md",
          "../../guides/architecture.md"
        ],
        Internals: [
          "docs/execution_plane_alignment.md",
          "docs/telemetry.md",
          "docs/dependency_policy.md"
        ]
      ]
    ]
  end
end
