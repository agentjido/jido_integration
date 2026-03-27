Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)

defmodule Jido.Integration.V2.ControlPlane.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_v2_control_plane,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Control Plane",
      description: "Capability registry and run ledger for the greenfield platform"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Jido.Integration.V2.ControlPlane.Application, []}
    ]
  end

  defp deps do
    [
      DependencyResolver.jido_integration_v2_contracts(),
      DependencyResolver.jido_integration_v2_auth(),
      DependencyResolver.jido_integration_v2_policy(),
      DependencyResolver.jido_integration_v2_direct_runtime(),
      DependencyResolver.jido_integration_v2_runtime_asm_bridge(),
      DependencyResolver.jido_session(),
      DependencyResolver.jido_harness(override: true),
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
        "../../guides/durability.md",
        "../../guides/async_and_webhooks.md",
        "../../guides/observability.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: [
          "../../guides/architecture.md",
          "../../guides/durability.md",
          "../../guides/async_and_webhooks.md",
          "../../guides/observability.md"
        ]
      ]
    ]
  end
end
