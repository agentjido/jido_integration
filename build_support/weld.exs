defmodule Jido.Integration.Build.WeldContract do
  @moduledoc false

  @tooling_projects [".", "core/conformance", "scaffolds/connector_generator"]
  @internal_projects ["core/connector_admission_engine"]
  @proof_projects ["apps/devops_incident_response", "apps/inference_ops"]

  @source_only_publication_projects [
    "connectors/amp",
    "connectors/codex_cli",
    "connectors/market_data",
    "core/runtime_control",
    "core/runtime_router",
    "core/asm_runtime_bridge",
    "core/session_runtime",
    "core/conformance_contracts",
    "core/connector_registry",
    "core/inference_operation_policy",
    "core/model_provider_registry",
    "core/provider_feature_matrix",
    "core/tool_contracts"
  ]

  @source_only_monolith_test_support_projects [
    "connectors/codex_cli",
    "connectors/market_data",
    "core/conformance",
    "core/conformance_contracts",
    "core/runtime_control",
    "core/runtime_router",
    "core/asm_runtime_bridge",
    "core/session_runtime"
  ]

  @published_roots [
    "connectors/amp",
    "connectors/github",
    "connectors/linear",
    "connectors/notion",
    "core/auth",
    "core/connector_admission_engine",
    "core/connector_registry",
    "core/consumer_surfaces",
    "core/contracts",
    "core/control_plane",
    "core/direct_runtime",
    "core/dispatch_runtime",
    "core/inference_operation_policy",
    "core/ingress",
    "core/model_provider_registry",
    "core/platform",
    "core/policy",
    "core/provider_feature_matrix",
    "core/tool_contracts",
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
    agent_session_manager: [requirement: "~> 0.9.2"],
    amp_sdk: [requirement: "~> 0.5.0"],
    cli_subprocess_core: [requirement: "~> 0.1.0"],
    execution_plane: [
      opts: [
        github: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "core/execution_plane",
        override: true
      ]
    ],
    execution_plane_jsonrpc: [
      opts: [
        github: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "protocols/execution_plane_jsonrpc",
        override: true
      ]
    ],
    execution_plane_process: [
      opts: [
        github: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "runtimes/execution_plane_process",
        override: true
      ]
    ],
    github_ex: [requirement: "~> 0.1.1"],
    ground_plane_persistence_policy: [
      opts: [
        github: "nshkrdotcom/ground_plane",
        branch: "main",
        subdir: "core/persistence_policy",
        override: true
      ]
    ],
    inference: [
      opts: [
        github: "nshkrdotcom/inference",
        branch: "main",
        subdir: "apps/inference"
      ]
    ],
    linear_sdk: [requirement: "~> 0.2.0"],
    notion_sdk: [requirement: "~> 0.2.1"],
    req_llm: [requirement: "~> 1.9"],
    telemetry: [requirement: "~> 1.4"]
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
        internal_only: @tooling_projects ++ @internal_projects,
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
          "GitHub" => "https://github.com/nshkrdotcom/jido_integration",
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
        ],
        hex_build: false,
        hex_publish: false
      ]
    ]
  end
end

Jido.Integration.Build.WeldContract.manifest()
