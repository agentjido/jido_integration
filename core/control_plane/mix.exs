defmodule Jido.Integration.V2.ControlPlane.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_control_plane,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Control Plane",
      description: "Capability registry and run ledger for the greenfield platform"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Jido.Integration.V2.ControlPlane.Application, []}
    ]
  end

  defp deps do
    agent_session_manager_path =
      basis_repo_path("AGENT_SESSION_MANAGER_PATH", "../../../agent_session_manager")

    [
      {:jido_integration_v2_contracts, path: "../contracts"},
      {:jido_integration_v2_auth, path: "../auth"},
      {:jido_integration_v2_policy, path: "../policy"},
      {:jido_integration_v2_direct_runtime, path: "../direct_runtime"},
      {:jido_integration_v2_runtime_asm_bridge, path: "../runtime_asm_bridge"},
      {:jido_harness,
       path: basis_repo_path("JIDO_HARNESS_PATH", "../../../jido_harness"), override: true},
      {:agent_session_manager, path: agent_session_manager_path, env: :dev},
      {:boundary,
       path: Path.join(agent_session_manager_path, "vendor/boundary"),
       only: [:dev, :test],
       runtime: false},
      {:jido_session, path: "../../../jido_session"},
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
