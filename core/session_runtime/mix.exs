defmodule Jido.Session.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_session,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Session Runtime",
      description: "Integration-owned internal `jido_session` Harness runtime"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Session.Application, []}
    ]
  end

  defp deps do
    [
      {:jido_harness,
       path: basis_repo_path("JIDO_HARNESS_PATH", "../../../jido_harness"), override: true},
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
      extras: [
        "README.md",
        "../../guides/runtime_model.md",
        "../../guides/architecture.md",
        "../../guides/developer/request_lifecycle.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: [
          "../../guides/runtime_model.md",
          "../../guides/architecture.md",
          "../../guides/developer/request_lifecycle.md"
        ]
      ]
    ]
  end

  defp basis_repo_path(env_var, default_path) do
    System.get_env(env_var, default_path)
  end
end
