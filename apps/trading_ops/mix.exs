unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

defmodule Jido.Integration.V2.Apps.TradingOps.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_v2_trading_ops,
      version: "0.1.0",
      elixir: "~> 1.19",
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
      DependencyResolver.jido_integration_v2(),
      DependencyResolver.jido_integration_v2_auth(),
      DependencyResolver.jido_integration_v2_contracts(),
      DependencyResolver.jido_integration_v2_harness_runtime(),
      DependencyResolver.jido_integration_v2_ingress(),
      DependencyResolver.jido_integration_v2_store_postgres(only: :test),
      DependencyResolver.jido_integration_v2_github(),
      DependencyResolver.jido_integration_v2_codex_cli(),
      DependencyResolver.jido_integration_v2_market_data(),
      DependencyResolver.req_llm(override: true),
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
