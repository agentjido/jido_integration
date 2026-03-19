defmodule Jido.Integration.V2.Apps.DevopsIncidentResponse.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_devops_incident_response,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Devops Incident Response",
      description: "Async webhook proof app above the greenfield platform"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jido_integration_v2, path: "../../core/platform"},
      {:jido_integration_v2_auth, path: "../../core/auth"},
      {:jido_integration_v2_contracts, path: "../../core/contracts"},
      {:jido_integration_v2_dispatch_runtime, path: "../../core/dispatch_runtime"},
      {:jido_integration_v2_webhook_router, path: "../../core/webhook_router"},
      {:jido_integration_v2_store_local, path: "../../core/store_local"},
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
      extras: ["README.md"]
    ]
  end
end
