defmodule Jido.Integration.V2.StreamRuntime.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_stream_runtime,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Stream Runtime",
      description: "Pull-oriented stream runtime for feed and protocol capabilities"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Integration.V2.StreamRuntime.Application, []}
    ]
  end

  defp deps do
    [
      {:jido_integration_v2_contracts, path: "../contracts"},
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
