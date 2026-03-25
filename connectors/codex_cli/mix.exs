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
      {:jido_integration_v2_consumer_surfaces, path: "../../core/consumer_surfaces"},
      {:jido_harness,
       path: basis_repo_path("JIDO_HARNESS_PATH", "../../../jido_harness"), override: true},
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

  defp basis_repo_path(env_var, default_path) do
    System.get_env(env_var, default_path)
  end
end
