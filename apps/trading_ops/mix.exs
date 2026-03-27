defmodule Jido.Integration.V2.Apps.TradingOps.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_trading_ops,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Trading Ops",
      description: "Reference operator app slice above the greenfield platform"
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
      {:jido_integration_v2_ingress, path: "../../core/ingress"},
      {:jido_integration_v2_store_postgres, path: "../../core/store_postgres", only: :test},
      {:jido_integration_v2_github, path: "../../connectors/github"},
      {:jido_integration_v2_codex_cli, path: "../../connectors/codex_cli"},
      {:jido_integration_v2_market_data, path: "../../connectors/market_data"},
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
