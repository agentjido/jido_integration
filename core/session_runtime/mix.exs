unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

defmodule Jido.Session.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_session,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Session Runtime",
      description: "Integration-owned internal `jido_session` Harness runtime"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Session.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      DependencyResolver.jido_harness(override: true),
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
        "../../guides/runtime_model.md",
        "../../guides/architecture.md",
        "../../guides/developer/request_lifecycle.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: [
          "../../guides/runtime_model.md",
          "../../guides/architecture.md",
          "../../guides/developer/request_lifecycle.md"
        ]
      ]
    ]
  end
end
