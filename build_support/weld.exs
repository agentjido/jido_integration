[
  workspace: [
    root: ".."
  ],
  classify: [
    tooling: [".", "core/conformance"],
    proofs: ["apps/devops_incident_response", "apps/trading_ops"]
  ],
  publication: [
    internal_only: [".", "core/conformance"],
    separate: [
      "connectors/codex_cli",
      "connectors/market_data",
      "core/harness_runtime",
      "core/runtime_asm_bridge",
      "core/session_runtime"
    ]
  ],
  dependencies: [
    agent_session_manager: [requirement: "~> 0.9.0"],
    github_ex: [requirement: "~> 0.1.0"],
    linear_sdk: [requirement: "~> 0.2.0"],
    notion_sdk: [requirement: "~> 0.2.0"],
    req_llm: [requirement: "~> 1.9"],
    self_hosted_inference_core: [requirement: "~> 0.1.0"],
    llama_cpp_sdk: [requirement: "~> 0.1.0"]
  ],
  artifacts: [
    jido_integration: [
      roots: [
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
      ],
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
        docs: [
          "README.md",
          "guides/index.md",
          "guides/architecture.md",
          "guides/runtime_model.md",
          "guides/inference_baseline.md",
          "guides/durability.md",
          "guides/connector_lifecycle.md",
          "guides/conformance.md",
          "guides/async_and_webhooks.md",
          "guides/publishing.md",
          "guides/reference_apps.md",
          "guides/observability.md",
          "guides/developer/index.md",
          "guides/developer/core_packages.md",
          "guides/developer/request_lifecycle.md",
          "guides/developer/state_and_verification.md"
        ],
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
  ]
]
