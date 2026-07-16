unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

defmodule Jido.Integration.SecretsProvider.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_secrets_provider,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration Secrets Provider",
      description: "Brokered secrets provider contract for governed lower invocations"
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto, :inets, :ssl]]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  defp deps do
    [
      DependencyResolver.jido_integration_v2_auth(env: Mix.env(), runtime: false),
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
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
