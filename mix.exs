defmodule Jido.Integration.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_integration"

  def project do
    [
      app: :jido_integration,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      name: "Jido Integration",
      source_url: @source_url,
      docs: docs(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
      preferred_cli_env: [
        conformance: :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Jido.Integration.Application, []}
    ]
  end

  defp elixirc_paths(:test) do
    [
      "lib",
      "test/support",
      "examples",
      "reference_apps/devops_incident_response/lib",
      "reference_apps/sales_pipeline/lib"
    ]
  end

  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jido_integration_contracts, path: "packages/core/contracts"},
      {:jido_integration_runtime, path: "packages/core/runtime"},
      {:jido_integration_conformance, path: "packages/core/conformance"},
      {:jido_integration_factory, path: "packages/core/factory"},
      {:jido_integration_http_common, path: "packages/core/http_common"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      conformance: ["test --only conformance"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      formatters: ["html", "markdown", "epub"],
      extras: [
        {"README.md", title: "Home"},

        # Introduction
        {"guides/00_overview.md", title: "Overview"},

        # Architecture
        {"guides/01_architecture.md", title: "Architecture"},
        {"guides/02_package_layout.md", title: "Package Layout"},

        # Core Concepts
        {"guides/03_runtime_and_durability.md", title: "Runtime & Durability"},
        {"guides/04_connector_factory.md", title: "Connector Factory"},

        # Testing & Quality
        {"guides/05_conformance.md", title: "Conformance Testing"},

        # Examples
        {"guides/06_reference_apps.md", title: "Reference Apps"},
        {"guides/07_live_examples.md", title: "Live Examples"},

        # Operations
        {"guides/08_operations_and_release.md", title: "Operations & Release"},

        # Project
        {"LICENSE", title: "Apache 2.0 License"}
      ],
      groups_for_extras: [
        Introduction: [
          "guides/00_overview.md"
        ],
        Architecture: [
          "guides/01_architecture.md",
          "guides/02_package_layout.md"
        ],
        "Core Concepts": [
          "guides/03_runtime_and_durability.md",
          "guides/04_connector_factory.md"
        ],
        "Testing & Quality": [
          "guides/05_conformance.md"
        ],
        Examples: [
          "guides/06_reference_apps.md",
          "guides/07_live_examples.md"
        ],
        Operations: [
          "guides/08_operations_and_release.md"
        ],
        Project: [
          "LICENSE"
        ]
      ],
      extra_section: "Guides",
      skip_undefined_reference_warnings_on: [
        "LICENSE"
      ],
      groups_for_modules: [
        Facade: [
          Jido.Integration,
          Jido.Integration.Application
        ],
        Contracts:
          ~r/^Jido\.Integration\.(Adapter|Auth|Capability|Error|Gateway|Manifest|Operation|Schema|Telemetry|Trigger|Webhook\.Route)/,
        Runtime:
          ~r/^Jido\.Integration\.(Auth\.Server|Dispatch|Registry|Webhook\.(Dedupe|Ingress|Router))/,
        Tooling: ~r/^Jido\.Integration\.Conformance/
      ]
    ]
  end
end
