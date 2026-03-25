defmodule Jido.Integration.V2.DispatchRuntime.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_dispatch_runtime,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Dispatch Runtime",
      description: "Async trigger dispatch runtime with retry, replay, and recovery"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:jido_integration_v2_contracts, path: "../contracts"},
      {:jido_integration_v2_control_plane, path: "../control_plane"},
      {:zoi, "~> 0.17"},
      {:telemetry, "~> 1.0"},
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
        "../../guides/async_and_webhooks.md",
        "../../guides/durability.md",
        "../../guides/observability.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: [
          "../../guides/async_and_webhooks.md",
          "../../guides/durability.md",
          "../../guides/observability.md"
        ]
      ]
    ]
  end
end
