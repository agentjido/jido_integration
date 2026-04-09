unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  Code.require_file("build_support/dependency_resolver.exs", __DIR__)
end

unless Code.ensure_loaded?(Jido.Integration.Build.WorkspaceContract) do
  Code.require_file("build_support/workspace_contract.exs", __DIR__)
end

defmodule Jido.Integration.Workspace.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.{DependencyResolver, WorkspaceContract}

  def project do
    [
      app: :jido_integration_workspace,
      version: "0.1.0",
      elixir: "~> 1.19",
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
      {:blitz, "~> 0.2.0", runtime: false},
      DependencyResolver.jido_integration_v2_conformance(),
      DependencyResolver.jido_integration_v2_contracts(),
      DependencyResolver.jido_shell(override: true, runtime: false),
      DependencyResolver.cli_subprocess_core(runtime: false),
      DependencyResolver.external_runtime_transport(runtime: false),
      DependencyResolver.sprites(override: true, runtime: false),
      {:libgraph, "== 0.16.1-mg.1", hex: :multigraph, app: false, override: true, runtime: false},
      DependencyResolver.req_llm(runtime: false),
      DependencyResolver.weld(runtime: false),
      {:jason, "~> 1.4", runtime: false},
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    monorepo_aliases = [
      "monorepo.deps.get": ["workspace.deps.get"],
      "monorepo.format": ["workspace.format"],
      "monorepo.compile": ["workspace.compile"],
      "monorepo.test": ["workspace.test"],
      "monorepo.credo": ["workspace.credo"],
      "monorepo.dialyzer": ["workspace.dialyzer"],
      "monorepo.docs": ["workspace.docs"]
    ]

    mr_aliases =
      ~w[deps.get format compile test credo dialyzer docs]
      |> Enum.map(fn task -> {:"mr.#{task}", ["monorepo.#{task}"]} end)

    [
      ci: [
        "monorepo.deps.get",
        "monorepo.format --check-formatted",
        "monorepo.compile",
        "monorepo.test",
        "monorepo.credo --strict",
        "monorepo.dialyzer",
        "monorepo.docs"
      ],
      quality: ["monorepo.credo --strict", "monorepo.dialyzer"],
      "docs.all": ["monorepo.docs"],
      "weld.inspect": ["weld.inspect build_support/weld.exs --artifact jido_integration"],
      "weld.graph": ["weld.graph build_support/weld.exs --artifact jido_integration"],
      "weld.project": ["weld.project build_support/weld.exs --artifact jido_integration"],
      "weld.verify": ["weld.verify build_support/weld.exs --artifact jido_integration"],
      "weld.release.prepare": [
        "weld.release.prepare build_support/weld.exs --artifact jido_integration"
      ],
      "weld.release.archive": [
        "weld.release.archive build_support/weld.exs --artifact jido_integration"
      ],
      "release.prepare": ["weld.release.prepare"],
      "release.publish.dry_run": ["jido_integration.release.publish --dry-run"],
      "release.publish": ["jido_integration.release.publish"],
      "release.archive": ["weld.release.archive"],
      "release.candidate": ["release.prepare", "release.publish.dry_run"]
    ] ++ monorepo_aliases ++ mr_aliases
  end

  defp dialyzer do
    [
      plt_add_deps: :apps_direct,
      plt_add_apps: [:mix, :blitz, :weld]
    ]
  end

  defp docs do
    [
      main: "workspace_readme",
      extras: [
        {"README.md", filename: "workspace_readme"},
        "AGENTS.md",
        {"guides/index.md", filename: "guides_index"},
        "guides/architecture.md",
        "guides/execution_plane_alignment.md",
        "guides/runtime_model.md",
        "guides/inference_baseline.md",
        "guides/durability.md",
        "guides/connector_lifecycle.md",
        "guides/conformance.md",
        "guides/async_and_webhooks.md",
        "guides/publishing.md",
        {"guides/reference_apps.md", filename: "guides_reference_apps"},
        "guides/observability.md",
        {"examples/README.md", filename: "examples_readme"},
        {"guides/developer/index.md", filename: "developer_index"},
        "guides/developer/core_packages.md",
        "guides/developer/request_lifecycle.md",
        "guides/developer/state_and_verification.md",
        "docs/architecture_overview.md",
        "docs/connector_review_baseline.md",
        "docs/connector_scaffolding.md",
        "docs/conformance_workflow.md",
        "docs/local_durability.md",
        "docs/async_dispatch_and_replay.md",
        "docs/webhook_routing.md",
        {"docs/reference_apps.md", filename: "docs_reference_apps"},
        "docs/observability_and_pressure_semantics.md"
      ],
      groups_for_extras: [
        Overview: ["README.md", "guides/index.md"],
        Architecture: [
          "guides/architecture.md",
          "guides/execution_plane_alignment.md",
          "docs/architecture_overview.md",
          "guides/runtime_model.md"
        ],
        Inference: ["guides/inference_baseline.md"],
        Durability: ["guides/durability.md", "docs/local_durability.md"],
        "Connector Lifecycle": [
          "guides/connector_lifecycle.md",
          "docs/connector_review_baseline.md",
          "docs/connector_scaffolding.md"
        ],
        Publication: ["guides/publishing.md"],
        Conformance: [
          "guides/conformance.md",
          "docs/conformance_workflow.md"
        ],
        "Async And Webhooks": [
          "guides/async_and_webhooks.md",
          "docs/async_dispatch_and_replay.md",
          "docs/webhook_routing.md"
        ],
        Operations: [
          "guides/reference_apps.md",
          "docs/reference_apps.md",
          "guides/observability.md",
          "docs/observability_and_pressure_semantics.md"
        ],
        Examples: ["examples/README.md"],
        Developer: [
          "guides/developer/index.md",
          "guides/developer/core_packages.md",
          "guides/developer/request_lifecycle.md",
          "guides/developer/state_and_verification.md"
        ]
      ]
    ]
  end

  def blitz_workspace_test_env(%{project_path: project_path} = context) do
    base_env = blitz_workspace_env(context)

    base_name =
      System.get_env(
        "JIDO_INTEGRATION_V2_DB_BASE_NAME",
        System.get_env("JIDO_INTEGRATION_V2_DB_NAME", "jido_integration_v2_test")
      )

    base_env ++
      [
        {"JIDO_INTEGRATION_V2_DB_BASE_NAME", base_name},
        {"JIDO_INTEGRATION_V2_DB_NAME",
         Blitz.MixWorkspace.hashed_project_name(base_name, project_path, max_bytes: 63)}
      ]
  end

  def blitz_workspace_env(%{root: root}) do
    repo_bin = Path.join(root, "bin")
    path = prepend_path(repo_bin, System.get_env("PATH"))

    [
      {"PATH", path},
      {"SSLKEYLOGFILE", nil}
    ]
  end

  defp blitz_workspace do
    [
      root: __DIR__,
      projects: WorkspaceContract.active_project_globs(),
      isolation: [
        deps_path: true,
        build_path: true,
        lockfile: true,
        hex_home: "_build/hex",
        unset_env: ["HEX_API_KEY", "SSLKEYLOGFILE"]
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
        deps_get: [
          args: ["deps.get"],
          preflight?: false,
          env: &__MODULE__.blitz_workspace_env/1
        ],
        format: [args: ["format"], env: &__MODULE__.blitz_workspace_env/1],
        test: [
          args: ["test"],
          mix_env: "test",
          color: true,
          env: &__MODULE__.blitz_workspace_test_env/1
        ],
        compile: [
          args: ["compile", "--warnings-as-errors"],
          env: &__MODULE__.blitz_workspace_env/1
        ],
        credo: [args: ["credo"], env: &__MODULE__.blitz_workspace_env/1],
        dialyzer: [
          args: ["dialyzer", "--force-check"],
          env: &__MODULE__.blitz_workspace_env/1
        ],
        docs: [args: ["docs"], env: &__MODULE__.blitz_workspace_env/1]
      ]
    ]
  end

  defp prepend_path(dir, nil), do: dir
  defp prepend_path(dir, ""), do: dir
  defp prepend_path(dir, path), do: dir <> ":" <> path
end
