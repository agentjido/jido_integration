unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)
end

defmodule Jido.Integration.V2.Apps.InferenceOps.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_v2_inference_ops,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Inference Ops",
      description: "Reference proof app for cloud and self-hosted inference execution"
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
      DependencyResolver.jido_integration_v2_control_plane(),
      DependencyResolver.jido_integration_contracts(),
      DependencyResolver.self_hosted_inference_core(),
      DependencyResolver.llama_cpp_sdk(),
      {:plug, "~> 1.19", only: [:dev, :test]},
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
      extras: [
        "README.md",
        "guides/proof_flow.md",
        {"examples/README.md", filename: "examples_readme"}
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: ["guides/proof_flow.md"],
        Examples: ["examples/README.md"]
      ]
    ]
  end
end
