defmodule Jido.Integration.Workspace.PackageSurfaceTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Build.{DependencyResolver, WorkspaceContract}
  alias Jido.Integration.Workspace.{MixProject, MonorepoRunner}

  @required_package_paths [
    ".formatter.exs",
    ".gitignore",
    "README.md",
    "mix.exs",
    "lib",
    "test"
  ]

  @required_package_mix_snippets [
    ~s(elixir: "~> 1.19"),
    "consolidate_protocols: false",
    "dialyzer: dialyzer()",
    "defp dialyzer do",
    "docs: docs()",
    "defp docs do",
    "{:credo,",
    "{:dialyxir,",
    "{:ex_doc,",
    "name:",
    "description:"
  ]

  test "workspace root exposes the canonical monorepo quality aliases" do
    aliases = MixProject.project()[:aliases]

    assert Keyword.fetch!(aliases, :ci) == [
             "monorepo.deps.get",
             "monorepo.format --check-formatted",
             "monorepo.compile",
             "monorepo.test",
             "monorepo.credo --strict",
             "monorepo.dialyzer",
             "monorepo.docs"
           ]

    for alias_name <- [
          :"monorepo.deps.get",
          :"monorepo.format",
          :"monorepo.compile",
          :"monorepo.test",
          :"monorepo.credo",
          :"monorepo.dialyzer",
          :"monorepo.docs",
          :"mr.deps.get",
          :"mr.format",
          :"mr.compile",
          :"mr.test",
          :"mr.credo",
          :"mr.dialyzer",
          :"mr.docs",
          :"weld.inspect",
          :"weld.graph",
          :"weld.project",
          :"weld.verify",
          :"weld.release.prepare",
          :"weld.release.archive",
          :"release.prepare",
          :"release.publish.dry_run",
          :"release.publish",
          :"release.archive",
          :"release.candidate"
        ] do
      assert Keyword.has_key?(aliases, alias_name),
             "expected workspace alias #{inspect(alias_name)} to exist"
    end
  end

  test "workspace root includes weld and the repo-local publication contract" do
    deps = MixProject.project()[:deps]

    assert Enum.any?(deps, fn
             {:weld, opts} when is_list(opts) ->
               Keyword.has_key?(opts, :path) or Keyword.has_key?(opts, :github)

             {:weld, requirement, opts} when is_binary(requirement) and is_list(opts) ->
               true

             {:weld, _requirement, opts} when is_list(opts) ->
               Keyword.has_key?(opts, :path) or Keyword.has_key?(opts, :github)

             _ ->
               false
           end),
           "workspace root must depend on weld through the shared dependency resolver"

    assert File.exists?(Path.join(repo_root(), "build_support/weld.exs"))
    assert File.exists?(Path.join(repo_root(), "build_support/workspace_contract.exs"))

    assert File.exists?(
             Path.join(repo_root(), "packaging/weld/jido_integration/test/test_helper.exs")
           )

    assert File.exists?(
             Path.join(
               repo_root(),
               "packaging/weld/jido_integration/test/public_surface_test.exs"
             )
           )

    assert File.exists?(Path.join(repo_root(), "packaging/weld/jido_integration/smoke.ex"))
  end

  test "shared dependency resolver honors weld path overrides and sibling fallback" do
    case System.get_env("WELD_PATH") do
      "disabled" ->
        assert {:weld, requirement, opts} = DependencyResolver.weld()
        assert requirement == "~> 0.4.0"
        refute Keyword.has_key?(opts, :path)

      override when is_binary(override) ->
        assert {:weld, opts} = DependencyResolver.weld()

        assert Path.expand(Keyword.fetch!(opts, :path), repo_root()) ==
                 Path.expand(override, repo_root())

      nil ->
        assert {:weld, opts} = DependencyResolver.weld()
        assert Path.expand(Keyword.fetch!(opts, :path)) == Path.expand("../weld", repo_root())
    end
  end

  test "weld contract keeps the published docs surface package-facing" do
    [{contract_module, _binary}] =
      Code.require_file("build_support/weld_contract.exs", repo_root())

    docs =
      contract_module.artifact()
      |> Keyword.fetch!(:output)
      |> Keyword.fetch!(:docs)

    assert "README.md" in docs
    assert "guides/execution_plane_alignment.md" in docs

    for path <- [
          "guides/reference_apps.md",
          "guides/developer/index.md",
          "guides/developer/core_packages.md",
          "guides/developer/request_lifecycle.md",
          "guides/developer/state_and_verification.md"
        ] do
      refute path in docs, "published docs should not ship #{path}"
    end
  end

  test "workspace isolation clears SSL key logging for monorepo verification tasks" do
    isolation = MixProject.project()[:blitz_workspace][:isolation]

    assert "SSLKEYLOGFILE" in isolation[:unset_env],
           "blitz workspace isolation must unset SSLKEYLOGFILE so Req-backed tasks do not fail on read-only home mounts"
  end

  test "workspace commands prefer the repo-local mix wrapper on PATH" do
    workspace = MixProject.project()[:blitz_workspace]
    env = Blitz.MixWorkspace.command_env(workspace, ".", :compile)
    path = env |> Enum.into(%{}) |> Map.fetch!("PATH")

    assert path |> String.split(":") |> hd() == Path.join(repo_root(), "bin"),
           "workspace child commands must resolve mix through the repo-local bin wrapper first"

    assert File.exists?(Path.join(repo_root(), "bin/mix")),
           "repo-local mix wrapper is missing from #{repo_root()}"
  end

  test "workspace scope is explicit about legacy source-only packages" do
    assert WorkspaceContract.active_project_globs() == [".", "core/*", "connectors/*", "apps/*"]
    assert WorkspaceContract.legacy_project_roots() == ["bridges/boundary_bridge"]
  end

  test "workspace runner resolves a real mix executable outside the repo wrapper" do
    workspace = Blitz.MixWorkspace.load!(MixProject.project()[:blitz_workspace])
    mix_command = MonorepoRunner.mix_command!(workspace)

    assert File.exists?(mix_command),
           "workspace runner must resolve an executable mix command, got: #{inspect(mix_command)}"

    assert Path.expand(mix_command) != Path.join(repo_root(), "bin/mix") |> Path.expand(),
           "workspace runner must not invoke the repo-local bin/mix wrapper directly"
  end

  test "child packages keep the baseline monorepo package structure" do
    for package_root <- child_package_roots() do
      for relative_path <- @required_package_paths do
        assert File.exists?(Path.join(package_root, relative_path)),
               "#{relative_path} is missing from #{Path.relative_to(package_root, repo_root())}"
      end
    end
  end

  test "child package mix projects expose the expected quality surfaces" do
    for mix_path <- child_package_mix_paths() do
      mix_exs = File.read!(mix_path)

      for snippet <- @required_package_mix_snippets do
        assert mix_exs =~ snippet,
               "#{Path.relative_to(mix_path, repo_root())} is missing #{inspect(snippet)}"
      end
    end
  end

  test "legacy Phase 6A bridge packages are absent from the workspace package graph" do
    for relative_path <- ["core/session_kernel", "core/stream_runtime"] do
      refute File.exists?(Path.join(repo_root(), relative_path)),
             "#{relative_path} must be deleted from the workspace"
    end
  end

  test "packages that compile agent_session_manager do not vendor its boundary compiler" do
    runtime_asm_bridge_mix =
      repo_root()
      |> Path.join("core/runtime_asm_bridge/mix.exs")
      |> File.read!()
      |> normalize_whitespace()

    assert runtime_asm_bridge_mix =~
             "Code.require_file(\"../../build_support/dependency_resolver.exs\", __DIR__)",
           "core/runtime_asm_bridge/mix.exs must load the shared dependency resolver"

    for required_snippet <- [
          "DependencyResolver.agent_session_manager(env: :dev)"
        ] do
      assert runtime_asm_bridge_mix =~ required_snippet,
             "core/runtime_asm_bridge/mix.exs is missing #{required_snippet}"
    end

    refute runtime_asm_bridge_mix =~ "DependencyResolver.boundary(",
           "core/runtime_asm_bridge/mix.exs must not depend on agent_session_manager/vendor/boundary"

    control_plane_mix =
      repo_root()
      |> Path.join("core/control_plane/mix.exs")
      |> File.read!()
      |> normalize_whitespace()

    refute control_plane_mix =~ "agent_session_manager_path =",
           "core/control_plane/mix.exs must not own agent_session_manager directly"

    refute control_plane_mix =~ "{:agent_session_manager,",
           "core/control_plane/mix.exs must route ASM through runtime_asm_bridge instead of depending on it directly"

    refute control_plane_mix =~ "{:boundary,",
           "core/control_plane/mix.exs must not expose ASM's boundary compiler directly"
  end

  test "control_plane reaches non-direct runtimes through the harness runtime package" do
    control_plane_mix =
      repo_root()
      |> Path.join("core/control_plane/mix.exs")
      |> File.read!()
      |> normalize_whitespace()

    assert control_plane_mix =~
             "DependencyResolver.jido_integration_v2_harness_runtime(only: :test)",
           "core/control_plane/mix.exs must keep the harness adapter behind a test-only package dependency"

    refute control_plane_mix =~ "DependencyResolver.jido_session()",
           "core/control_plane/mix.exs must not depend on the session runtime package directly"

    refute control_plane_mix =~ "../../../jido_session",
           "core/control_plane/mix.exs must not depend on a sibling jido_session repo checkout"
  end

  defp child_package_roots do
    repo_root()
    |> Path.join("{core,bridges,connectors,apps}/*/mix.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.dirname/1)
    |> Enum.sort()
  end

  defp child_package_mix_paths do
    repo_root()
    |> Path.join("{core,bridges,connectors,apps}/*/mix.exs")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp repo_root, do: Path.expand("../..", __DIR__)

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
