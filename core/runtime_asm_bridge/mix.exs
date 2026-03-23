defmodule Jido.Integration.V2.RuntimeAsmBridge.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_runtime_asm_bridge,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Runtime ASM Bridge",
      description: "Integration-owned ASM-backed Harness runtime driver"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Integration.V2.RuntimeAsmBridge.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jido_harness, path: "../../../jido_harness"},
      {:agent_session_manager, path: "../../../agent_session_manager"},
      {:boundary, path: "../../../agent_session_manager/vendor/boundary", runtime: false},
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [plt_add_deps: :apps_tree]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
