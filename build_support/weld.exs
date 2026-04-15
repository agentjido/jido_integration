defmodule Jido.Integration.Build.WeldContract do
  @moduledoc false

  @tooling_projects [".", "core/conformance"]
  @proof_projects ["apps/devops_incident_response", "apps/inference_ops"]

  @source_only_publication_projects [
    "connectors/codex_cli",
    "connectors/market_data",
    "core/runtime_control",
    "core/runtime_router",
    "core/asm_runtime_bridge",
    "core/session_runtime"
  ]

  @source_only_monolith_test_support_projects [
    "connectors/codex_cli",
    "connectors/market_data",
    "core/conformance",
    "core/runtime_control",
    "core/runtime_router",
    "core/asm_runtime_bridge",
    "core/session_runtime"
  ]

  @published_roots [
    "connectors/github",
    "connectors/linear",
    "connectors/notion",
    "core/auth",
    "core/consumer_surfaces",
    "core/contracts",
    "core/control_plane",
    "core/direct_runtime",
    "core/dispatch_runtime",
    "core/ingress",
    "core/platform",
    "core/policy",
    "core/store_local",
    "core/store_postgres",
    "core/webhook_router"
  ]

  @artifact_docs [
    "README.md",
    "guides/index.md",
    "guides/architecture.md",
    "guides/execution_plane_alignment.md",
    "guides/runtime_model.md",
    "guides/inference_baseline.md",
    "guides/durability.md",
    "guides/connector_lifecycle.md",
    "guides/conformance.md",
    "guides/async_and_webhooks.md",
    "guides/publishing.md",
    "guides/observability.md"
  ]

  @dependencies [
    agent_session_manager: [requirement: "~> 0.9.1"],
    github_ex: [requirement: "~> 0.1.0"],
    linear_sdk: [requirement: "~> 0.2.0"],
    notion_sdk: [requirement: "~> 0.2.0"],
    req_llm: [requirement: "~> 1.9"]
  ]

  def manifest do
    [
      workspace: [
        root: ".."
      ],
      classify: [
        tooling: @tooling_projects,
        proofs: @proof_projects
      ],
      publication: [
        internal_only: @tooling_projects,
        separate: @source_only_publication_projects
      ],
      dependencies: @dependencies,
      artifacts: [
        jido_integration: artifact()
      ]
    ]
  end

  def artifact do
    [
      mode: :monolith,
      monolith_opts: [
        test_support_projects: @source_only_monolith_test_support_projects
      ],
      roots: @published_roots,
      package: [
        name: "jido_integration",
        otp_app: :jido_integration,
        version: "0.1.0",
        description: "Unified Jido Integration package generated from the source monorepo",
        licenses: ["Apache-2.0"],
        maintainers: ["nshkrdotcom"],
        links: %{
          "GitHub" => "https://github.com/agentjido/jido_integration",
          "Guides" => "https://hexdocs.pm/jido_integration/readme.html"
        }
      ],
      output: [
        docs: @artifact_docs,
        assets: ["LICENSE"]
      ],
      verify: [
        artifact_tests: ["packaging/weld/jido_integration/test"],
        smoke: [
          enabled: true,
          entry_file: "packaging/weld/jido_integration/smoke.ex"
        ]
      ]
    ]
  end
end

Jido.Integration.Build.WeldContract.manifest()
