Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)

defmodule Jido.Integration.V2.ConsumerSurfaces.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_v2_consumer_surfaces,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Consumer Surfaces",
      description: "Runtime support for generated Jido-native consumer surfaces"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      DependencyResolver.jido_integration_v2_contracts(),
      DependencyResolver.jido_integration_v2_control_plane(),
      DependencyResolver.jido_integration_v2_ingress(),
      {:jido, "~> 2.1"},
      {:jido_action, "~> 2.1"},
      {:jido_signal, "~> 2.0"},
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
        "../../guides/architecture.md",
        "../../guides/async_and_webhooks.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: [
          "../../guides/architecture.md",
          "../../guides/async_and_webhooks.md"
        ]
      ]
    ]
  end
end
