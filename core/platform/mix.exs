defmodule Jido.Integration.V2.Platform.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Platform",
      description: "Public facade package for the Jido Integration platform"
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
      {:jido_integration_v2_control_plane, path: "../control_plane"},
      {:jido_integration_v2_store_postgres, path: "../store_postgres", only: :test},
      {:jido_integration_v2_github, path: "../../connectors/github", only: :test},
      {:jido_integration_v2_codex_cli, path: "../../connectors/codex_cli", only: :test},
      {:jido_integration_v2_market_data, path: "../../connectors/market_data", only: :test},
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
