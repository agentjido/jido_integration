defmodule JidoIntegration.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration,
      version: "0.1.0",
      build_path: "_build",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      erlc_paths: [],
      deps: deps(),
      description: "Unified Jido Integration package generated from the source monorepo",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      mod: {JidoIntegration.Application, []},
      extra_applications: [:crypto, :ecto_sql, :inets, :logger, :ssl]
    ]
  end

  def elixirc_paths(:test) do
    if File.dir?("test/support") do
      ["lib", "test/support"]
    else
      ["lib"]
    end
  end

  def elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:agent_session_manager, "~> 0.9.1", [env: :dev]},
      {:ecto, "~> 3.13.4"},
      {:ecto_sql, "~> 3.13.4"},
      {:github_ex, "~> 0.1.0", []},
      {:jason, "~> 1.4"},
      {:jcs, "~> 0.2.0"},
      {:jido, "~> 2.2"},
      {:jido_action, "~> 2.2"},
      {:jido_signal, "~> 2.1"},
      {:linear_sdk, "~> 0.2.0", []},
      {:notion_sdk, "~> 0.2.0", []},
      {:postgrex, "~> 0.21.1"},
      {:req_llm, "~> 1.9", []},
      {:self_hosted_inference_core, "~> 0.1.0"},
      {:splode, "~> 0.3.0", []},
      {:telemetry, "~> 1.0"},
      {:zoi, "~> 0.17"},
      {:sprites,
       [
         only: :test,
         git: "https://github.com/mikehostetler/sprites-ex.git",
         branch: "main",
         optional: true,
         override: true
       ]},
      {:credo, "~> 1.7.17", [only: [:dev, :test], runtime: false]},
      {:dialyxir, "~> 1.4.7", [only: [:dev, :test], runtime: false]},
      {:ex_doc, "~> 0.40.1", [only: :dev, runtime: false]},
      {:llama_cpp_sdk, "~> 0.1.0", [only: :test]},
      {:plug, "~> 1.19", [only: [:dev, :test]]}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["nshkrdotcom"],
      links: %{
        "GitHub" => "https://github.com/agentjido/jido_integration",
        "Guides" => "https://hexdocs.pm/jido_integration/readme.html"
      },
      files: [
        ".formatter.exs",
        "LICENSE",
        "README.md",
        "config",
        "guides",
        "lib",
        "mix.exs",
        "priv",
        "projection.lock.json"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/architecture.md",
        "guides/async_and_webhooks.md",
        "guides/conformance.md",
        "guides/connector_lifecycle.md",
        "guides/durability.md",
        "guides/execution_plane_alignment.md",
        "guides/index.md",
        "guides/inference_baseline.md",
        "guides/observability.md",
        "guides/publishing.md",
        "guides/runtime_model.md"
      ]
    ]
  end
end
