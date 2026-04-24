unless Code.ensure_loaded?(Jido.Integration.Build.DependencyResolver) do
  resolver_path = Path.expand("../../build_support/dependency_resolver.exs", __DIR__)

  if File.regular?(resolver_path) do
    Code.require_file(resolver_path)
  else
    defmodule Jido.Integration.Build.DependencyResolver do
      @moduledoc false

      @repo_root Path.expand("../..", __DIR__)

      def jido_integration_contracts(opts \\ []),
        do: git_dep(:jido_integration_contracts, "core/contracts", opts)

      def jido_integration_v2_auth(opts \\ []),
        do: git_dep(:jido_integration_v2_auth, "core/auth", opts)

      def jido_integration_v2_brain_ingress(opts \\ []),
        do: git_dep(:jido_integration_v2_brain_ingress, "core/brain_ingress", opts)

      def jido_integration_v2_control_plane(opts \\ []),
        do: git_dep(:jido_integration_v2_control_plane, "core/control_plane", opts)

      def jido_integration_v2_runtime_router(opts \\ []),
        do: git_dep(:jido_integration_v2_runtime_router, "core/runtime_router", opts)

      def jido_integration_v2_store_postgres(opts \\ []),
        do: git_dep(:jido_integration_v2_store_postgres, "core/store_postgres", opts)

      def jido_integration_v2_github(opts \\ []),
        do: git_dep(:jido_integration_v2_github, "connectors/github", opts)

      def jido_integration_v2_codex_cli(opts \\ []),
        do: git_dep(:jido_integration_v2_codex_cli, "connectors/codex_cli", opts)

      def jido_integration_v2_market_data(opts \\ []),
        do: git_dep(:jido_integration_v2_market_data, "connectors/market_data", opts)

      def req_llm(opts \\ []), do: {:req_llm, "~> 1.9", opts}

      def splode(opts \\ []), do: {:splode, "~> 0.3.0", opts}

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
