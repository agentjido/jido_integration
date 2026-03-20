defmodule Jido.Integration.V2.Connectors.CodexCli.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_codex_cli,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Codex CLI Connector",
      description: "Example session connector package for the greenfield platform"
    ]
  end

  defp elixirc_paths(env) when env in [:dev, :test], do: ["lib", "test_support"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jido, "~> 2.1"},
      {:jido_action, "~> 2.1"},
      {:jido_integration_v2_contracts, path: "../../core/contracts"},
      {:jido_harness, path: "../../../jido_harness", only: [:dev, :test]},
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
