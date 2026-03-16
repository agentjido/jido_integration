defmodule Jido.Integration.V2.SessionKernel.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_session_kernel,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Session Kernel",
      description: "Migration shim for legacy session providers behind Harness runtime routing"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Jido.Integration.V2.SessionKernel.Application, []}
    ]
  end

  defp deps do
    [
      {:jido_integration_v2_contracts, path: "../contracts"},
      {:jido_harness, path: "../../../jido_harness"},
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
