Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)

defmodule Jido.Integration.V2.Conformance.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_v2_conformance,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Conformance",
      description: "Reusable v2-native connector conformance engine and report surface"
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
      DependencyResolver.jido_integration_v2_control_plane(),
      DependencyResolver.jido_integration_v2_direct_runtime(),
      DependencyResolver.jido_integration_v2_ingress(),
      DependencyResolver.jido_integration_v2(only: :test, runtime: false),
      DependencyResolver.jido_integration_v2_github(only: :test),
      {:zoi, "~> 0.17"},
      {:jason, "~> 1.4"},
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
        "../../guides/connector_lifecycle.md",
        "../../guides/conformance.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: [
          "../../guides/connector_lifecycle.md",
          "../../guides/conformance.md"
        ]
      ]
    ]
  end
end
