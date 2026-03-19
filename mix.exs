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
      blitz_workspace: blitz_workspace(),
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
    monorepo_aliases = [
      "monorepo.deps.get": ["blitz.workspace deps_get"],
      "monorepo.format": ["blitz.workspace format"],
      "monorepo.compile": ["blitz.workspace compile"],
      "monorepo.test": ["blitz.workspace test"],
      "monorepo.credo": ["blitz.workspace credo"],
      "monorepo.dialyzer": ["blitz.workspace dialyzer"],
      "monorepo.docs": ["blitz.workspace docs"]
    ]

    mr_aliases =
      ~w[deps.get format compile test credo dialyzer docs]
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
    ] ++ monorepo_aliases ++ mr_aliases
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

  def blitz_workspace_test_env(%{project_path: project_path}) do
    base_name =
      System.get_env(
        "JIDO_INTEGRATION_V2_DB_BASE_NAME",
        System.get_env("JIDO_INTEGRATION_V2_DB_NAME", "jido_integration_v2_test")
      )

    [
      {"JIDO_INTEGRATION_V2_DB_BASE_NAME", base_name},
      {"JIDO_INTEGRATION_V2_DB_NAME",
       Blitz.MixWorkspace.hashed_project_name(base_name, project_path, max_bytes: 63)}
    ]
  end

  defp blitz_workspace do
    [
      root: __DIR__,
      projects: [".", "core/*", "connectors/*", "apps/*"],
      isolation: [
        deps_path: true,
        build_path: true,
        lockfile: true,
        hex_home: "_build/hex",
        unset_env: ["HEX_API_KEY"]
      ],
      parallelism: [
        env: "JIDO_MONOREPO_MAX_CONCURRENCY",
        multiplier: :auto,
        base: [
          deps_get: 3,
          format: 4,
          compile: 2,
          test: 2,
          credo: 2,
          dialyzer: 1,
          docs: 1
        ],
        overrides: []
      ],
      tasks: [
        deps_get: [args: ["deps.get"], preflight?: false],
        format: [args: ["format"]],
        compile: [args: ["compile", "--warnings-as-errors"]],
        test: [
          args: ["test"],
          mix_env: "test",
          color: true,
          env: &__MODULE__.blitz_workspace_test_env/1
        ],
        credo: [args: ["credo"]],
        dialyzer: [args: ["dialyzer", "--force-check"]],
        docs: [args: ["docs"]]
      ]
    ]
  end
end
