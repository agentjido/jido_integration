defmodule Jido.Integration.V2.WebhookRouter.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_webhook_router,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Webhook Router",
      description: "Hosted webhook route registration and dispatch bridging above ingress"
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
      {:jido_integration_v2_auth, path: "../auth"},
      {:jido_integration_v2_ingress, path: "../ingress"},
      {:jido_integration_v2_dispatch_runtime, path: "../dispatch_runtime"},
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
        "../../guides/architecture.md",
        "../../guides/observability.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: [
          "../../guides/async_and_webhooks.md",
          "../../guides/architecture.md",
          "../../guides/observability.md"
        ]
      ]
    ]
  end
end
