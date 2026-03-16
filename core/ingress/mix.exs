defmodule Jido.Integration.V2.Ingress.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_ingress,
      version: "0.1.0",
      elixir: "~> 1.18",
      consolidate_protocols: Mix.env() != :test,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Ingress",
      description: "Webhook and polling trigger admission for the greenfield platform"
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
      {:jido_signal, "~> 2.0"},
      {:jido_integration_v2_store_postgres, path: "../store_postgres", only: :test},
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
