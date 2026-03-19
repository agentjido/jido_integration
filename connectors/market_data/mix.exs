defmodule Jido.Integration.V2.Connectors.MarketData.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_market_data,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Market Data Connector",
      description: "Example stream connector package for feed-style capabilities"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jido_integration_v2_contracts, path: "../../core/contracts"},
      {:jido_integration_v2_stream_runtime, path: "../../core/stream_runtime"},
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
