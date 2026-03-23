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
    agent_session_manager_path =
      basis_repo_path("AGENT_SESSION_MANAGER_PATH", "../../../agent_session_manager")

    [
      {:jido_harness,
       path: basis_repo_path("JIDO_HARNESS_PATH", "../../../jido_harness"), override: true},
      {:agent_session_manager, path: agent_session_manager_path, env: :dev},
      {:boundary,
       path: Path.join(agent_session_manager_path, "vendor/boundary"),
       only: [:dev, :test],
       runtime: false},
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

  defp basis_repo_path(env_var, default_path) do
    System.get_env(env_var, default_path)
  end
end
