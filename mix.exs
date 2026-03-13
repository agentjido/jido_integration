defmodule Jido.Integration.V2.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2",
      description: "Greenfield capability control plane with direct and session runtimes"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:jido_integration_v2_contracts, path: "packages/core/contracts"},
      {:jido_integration_v2_control_plane, path: "packages/core/control_plane"},
      {:jido_integration_v2_auth, path: "packages/core/auth"},
      {:jido_integration_v2_store_postgres, path: "packages/core/store_postgres"},
      {:jido_integration_v2_policy, path: "packages/core/policy"},
      {:jido_integration_v2_direct_runtime, path: "packages/core/direct_runtime"},
      {:jido_integration_v2_ingress, path: "packages/core/ingress"},
      {:jido_integration_v2_session_kernel, path: "packages/core/session_kernel"},
      {:jido_integration_v2_stream_runtime, path: "packages/core/stream_runtime"},
      {:jido_integration_v2_github, path: "packages/connectors/github"},
      {:jido_integration_v2_codex_cli, path: "packages/connectors/codex_cli"},
      {:jido_integration_v2_market_data, path: "packages/connectors/market_data"},
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    mr_aliases =
      ~w[compile test format credo dialyzer docs deps.get]
      |> Enum.map(fn task -> {:"mr.#{task}", ["monorepo.#{task}"]} end)

    [
      ci: [
        "monorepo.format --check-formatted",
        "monorepo.compile",
        "monorepo.test",
        "monorepo.credo --strict",
        "monorepo.dialyzer",
        "monorepo.docs"
      ],
      quality: ["monorepo.credo --strict", "monorepo.dialyzer"],
      "docs.all": ["monorepo.docs"]
    ] ++ mr_aliases
  end

  defp dialyzer do
    [
      plt_add_deps: :apps_direct,
      plt_add_apps: [:mix]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "docs/connector_review_baseline.md"]
    ]
  end
end
