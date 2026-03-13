defmodule Jido.Integration.V2.Conformance.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_conformance,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Conformance",
      description: "Reusable v2-native connector conformance engine and report surface"
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
      {:jido_integration_v2_direct_runtime, path: "../direct_runtime"},
      {:jido_integration_v2_session_kernel, path: "../session_kernel"},
      {:jido_integration_v2_stream_runtime, path: "../stream_runtime"},
      {:jido_integration_v2_ingress, path: "../ingress"},
      {:jido_integration_v2_github, path: "../../connectors/github", only: :test},
      {:jason, "~> 1.4"},
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
