unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  resolver_path = Path.expand("../../build_support/dependency_resolver.exs", __DIR__)

  if File.regular?(resolver_path) do
    Code.require_file(resolver_path)
  else
    defmodule Jido.Integration.Build.DependencyResolver do
      @moduledoc false

      @repo_root Path.expand("../..", __DIR__)

      def jido_integration_v2(opts \\ []),
        do: git_dep(:jido_integration_v2, "core/platform", opts)

      def jido_integration_contracts(opts \\ []),
        do: git_dep(:jido_integration_contracts, "core/contracts", opts)

      def jido_integration_v2_auth(opts \\ []),
        do: git_dep(:jido_integration_v2_auth, "core/auth", opts)

      def jido_integration_v2_brain_ingress(opts \\ []),
        do: git_dep(:jido_integration_v2_brain_ingress, "core/brain_ingress", opts)

      def jido_integration_v2_conformance(opts \\ []),
        do: git_dep(:jido_integration_v2_conformance, "core/conformance", opts)

      def jido_integration_v2_consumer_surfaces(opts \\ []),
        do: git_dep(:jido_integration_v2_consumer_surfaces, "core/consumer_surfaces", opts)

      def jido_integration_v2_control_plane(opts \\ []),
        do: git_dep(:jido_integration_v2_control_plane, "core/control_plane", opts)

      def jido_integration_v2_direct_runtime(opts \\ []),
        do: git_dep(:jido_integration_v2_direct_runtime, "core/direct_runtime", opts)

      def jido_integration_v2_dispatch_runtime(opts \\ []),
        do: git_dep(:jido_integration_v2_dispatch_runtime, "core/dispatch_runtime", opts)

      def jido_integration_v2_ingress(opts \\ []),
        do: git_dep(:jido_integration_v2_ingress, "core/ingress", opts)

      def jido_integration_v2_policy(opts \\ []),
        do: git_dep(:jido_integration_v2_policy, "core/policy", opts)

      def jido_integration_v2_asm_runtime_bridge(opts \\ []),
        do: git_dep(:jido_integration_v2_asm_runtime_bridge, "core/asm_runtime_bridge", opts)

      def jido_runtime_control(opts \\ []),
        do: git_dep(:jido_runtime_control, "core/runtime_control", opts)

      def jido_integration_v2_store_local(opts \\ []),
        do: git_dep(:jido_integration_v2_store_local, "core/store_local", opts)

      def jido_integration_v2_runtime_router(opts \\ []),
        do: git_dep(:jido_integration_v2_runtime_router, "core/runtime_router", opts)

      def jido_integration_v2_store_postgres(opts \\ []),
        do: git_dep(:jido_integration_v2_store_postgres, "core/store_postgres", opts)

      def jido_integration_v2_webhook_router(opts \\ []),
        do: git_dep(:jido_integration_v2_webhook_router, "core/webhook_router", opts)

      def jido_session(opts \\ []),
        do: git_dep(:jido_session, "core/session_runtime", opts)

      def jido_integration_v2_github(opts \\ []),
        do: git_dep(:jido_integration_v2_github, "connectors/github", opts)

      def jido_integration_v2_codex_cli(opts \\ []),
        do: git_dep(:jido_integration_v2_codex_cli, "connectors/codex_cli", opts)

      def jido_integration_v2_linear(opts \\ []),
        do: git_dep(:jido_integration_v2_linear, "connectors/linear", opts)

      def jido_integration_v2_market_data(opts \\ []),
        do: git_dep(:jido_integration_v2_market_data, "connectors/market_data", opts)

      def jido_integration_v2_notion(opts \\ []),
        do: git_dep(:jido_integration_v2_notion, "connectors/notion", opts)

      def jido_integration_v2_devops_incident_response(opts \\ []),
        do:
          git_dep(
            :jido_integration_v2_devops_incident_response,
            "apps/devops_incident_response",
            opts
          )

      def jido_integration_v2_inference_ops(opts \\ []),
        do: git_dep(:jido_integration_v2_inference_ops, "apps/inference_ops", opts)

      def agent_session_manager(opts \\ []), do: {:agent_session_manager, "~> 0.9.2", opts}

      def cli_subprocess_core(opts \\ []), do: {:cli_subprocess_core, "~> 0.1.0", opts}

      def jido_action(opts \\ []), do: {:jido_action, "~> 2.2", opts}

      def req_llm(opts \\ []), do: {:req_llm, "~> 1.9", opts}

      def splode(opts \\ []), do: {:splode, "~> 0.3.0", opts}

      def pristine(opts \\ []), do: {:pristine, "~> 0.2.1", opts}

      def self_hosted_inference_core(opts \\ []),
        do: {:self_hosted_inference_core, "~> 0.1.0", opts}

      def llama_cpp_sdk(opts \\ []), do: {:llama_cpp_sdk, "~> 0.1.0", opts}

      defp git_dep(app, subdir, opts) do
        source_opts =
          [git: repo_source(), subdir: subdir]
          |> maybe_put_branch(repo_branch())

        {app, Keyword.merge(source_opts, opts)}
      end

      defp repo_source do
        case git_config("remote.origin.url") do
          nil -> @repo_root
          "" -> @repo_root
          value -> value
        end
      end

      defp repo_branch do
        case git_config("branch.#{current_branch()}.merge") do
          "refs/heads/" <> branch -> branch
          _ -> current_branch()
        end
      end

      defp current_branch do
        case git(["rev-parse", "--abbrev-ref", "HEAD"]) do
          "HEAD" -> nil
          branch -> branch
        end
      end

      defp maybe_put_branch(opts, nil), do: opts
      defp maybe_put_branch(opts, ""), do: opts
      defp maybe_put_branch(opts, branch), do: Keyword.put(opts, :branch, branch)

      defp git_config(key), do: git(["config", "--get", key])

      defp git(args) do
        case System.cmd("git", ["-C", @repo_root] ++ args, stderr_to_stdout: true) do
          {value, 0} -> String.trim(value)
          _ -> nil
        end
      end
    end
  end
end

defmodule Jido.Integration.V2.Platform.MixProject do
  use Mix.Project

  alias Jido.Integration.Build.DependencyResolver

  def project do
    [
      app: :jido_integration_v2,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Platform",
      description: "Public facade package for the Jido Integration platform"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      DependencyResolver.jido_integration_contracts(),
      DependencyResolver.jido_integration_v2_auth(),
      DependencyResolver.jido_integration_v2_brain_ingress(),
      DependencyResolver.jido_integration_v2_control_plane(),
      DependencyResolver.jido_integration_v2_runtime_router(only: :test),
      DependencyResolver.jido_integration_v2_store_postgres(only: :test),
      DependencyResolver.jido_integration_v2_github(only: :test),
      DependencyResolver.jido_integration_v2_codex_cli(only: :test),
      DependencyResolver.jido_integration_v2_market_data(only: :test),
      DependencyResolver.req_llm(),
      DependencyResolver.splode(),
      {:plug, "~> 1.19", only: [:dev, :test]},
      {:zoi, "~> 0.17"},
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [plt_add_deps: :apps_direct]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/inference_review_packets.md",
        {"examples/README.md", filename: "examples_readme"},
        "../../guides/inference_baseline.md",
        "../../guides/architecture.md",
        "../../guides/runtime_model.md",
        "../../guides/connector_lifecycle.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Inference: [
          "guides/inference_review_packets.md",
          "../../guides/inference_baseline.md"
        ],
        Examples: ["examples/README.md"],
        Guides: [
          "../../guides/architecture.md",
          "../../guides/runtime_model.md",
          "../../guides/connector_lifecycle.md"
        ]
      ]
    ]
  end
end
