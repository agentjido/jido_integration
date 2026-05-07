Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)

defmodule Jido.Integration.ConnectorAdmissionEngine.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_connector_admission_engine,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration Connector Admission Engine",
      description: "Memory-default connector admission records for the companion lane"
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      DependencyResolver.jido_integration_contracts(),
      DependencyResolver.ground_plane_persistence_policy(),
      DependencyResolver.jido_integration_conformance_contracts(only: :test, runtime: false),
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [plt_add_deps: :apps_direct]
  end

  defp docs do
    [main: "readme", extras: ["README.md"]]
  end
end
