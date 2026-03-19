defmodule Jido.Integration.Workspace.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_workspace,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration Workspace",
      description: "Tooling root for the Jido Integration non-umbrella monorepo"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:blitz, path: "../blitz"},
      {:jido_integration_v2_conformance, path: "core/conformance"},
      {:jido_integration_v2_contracts, path: "core/contracts"},
      {:jason, "~> 1.4", runtime: false},
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
      extras: [
        "README.md",
        "AGENTS.md",
        "docs/architecture_overview.md",
        "docs/connector_review_baseline.md",
        "docs/connector_scaffolding.md",
        "docs/conformance_workflow.md",
        "docs/local_durability.md",
        "docs/async_dispatch_and_replay.md",
        "docs/webhook_routing.md",
        "docs/reference_apps.md",
        "docs/observability_and_pressure_semantics.md"
      ]
    ]
  end
end
