defmodule Jido.Integration.V2.DirectRuntime.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_direct_runtime,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Direct Runtime",
      description: "Direct execution runtime for stateless and request/response capabilities"
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
      {:jido_action, path: "../../../../../../jido_action"},
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
