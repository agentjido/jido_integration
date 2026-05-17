defmodule Jido.Integration.Workspace.PackageSurfaceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.Build.{DependencyResolver, WorkspaceContract}
  alias Jido.Integration.Workspace.{MixProject, MonorepoRunner}
  alias Mix.Tasks.Workspace.Impact.Ci

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

    assert Keyword.fetch!(aliases, :ci) == ["workspace.impact.ci"]

    assert Keyword.fetch!(aliases, :"ci.full") == [
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
          :"ci.full",
          :"mr.deps.get",
          :"mr.format",
          :"mr.compile",
          :"mr.test",
          :"mr.credo",
          :"mr.dialyzer",
          :"mr.docs",
          :"scaffold.validate",
          :"release.publish.dry_run",
          :"release.publish",
          :"release.candidate"
        ] do
      assert Keyword.has_key?(aliases, alias_name),
             "expected workspace alias #{inspect(alias_name)} to exist"
    end

    for alias_name <- [
          :"weld.inspect",
          :"weld.graph",
          :"weld.project",
          :"weld.verify",
          :"weld.release.prepare",
          :"weld.release.track",
          :"weld.release.archive",
          :"release.prepare",
          :"release.track",
          :"release.archive"
        ] do
      refute Keyword.has_key?(aliases, alias_name),
             "expected workspace alias #{inspect(alias_name)} to be removed"
    end
  end

  test "workspace root uses the published Blitz impact runner by default" do
    deps = MixProject.project()[:deps]

    assert {:blitz, "~> 0.3.0", runtime: false} in deps,
           "workspace root must default to the published Blitz 0.3.0 release line"

    assert Ci.local_blitz_dep_path(MixProject.project()) == nil
    assert Ci.ensure_local_blitz_current!() == :current

    assert Code.ensure_loaded?(Ci)

    assert Ci.impact_policy() == [
             workspace_invalidators: [
               "build_support/dependency_resolver.exs",
               "build_support/dependency_sources.exs",
               "build_support/dependency_sources.config.exs",
               "build_support/workspace_contract.exs"
             ],
             aggregate_docs_projects: [],
             test_dependency_fanout: :source_only,
             deps_get_lockfile_self_invalidation: false
           ]
  end

  test "workspace impact CI still supports local Blitz path overrides" do
    project_config =
      Keyword.put(MixProject.project(), :deps, [{:blitz, path: "../blitz", runtime: false}])

    assert Ci.local_blitz_dep_path(project_config) == Path.expand("../blitz", repo_root())

    fingerprint = Ci.local_blitz_source_fingerprint(Ci.local_blitz_dep_path(project_config))

    assert is_binary(fingerprint)
    assert byte_size(fingerprint) == 64
  end

  test "workspace impact CI recompiles local Blitz only when source changes" do
    tmp_root =
      System.tmp_dir!()
      |> Path.join("jido_blitz_fingerprint_#{System.unique_integer([:positive])}")

    stamp_path = Path.join([tmp_root, "_build", "stamp"])
    parent = self()

    File.rm_rf!(tmp_root)
    File.mkdir_p!(Path.join(tmp_root, "lib"))
    File.mkdir_p!(Path.join(tmp_root, "_build"))
    File.mkdir_p!(Path.join(tmp_root, ".blitz"))
    File.write!(Path.join(tmp_root, "mix.exs"), "defmodule Demo.MixProject do\nend\n")
    File.write!(Path.join(tmp_root, "lib/demo.ex"), "defmodule Demo do\nend\n")

    compile_fun = fn path ->
      send(parent, {:compiled, path})
      :ok
    end

    try do
      assert Ci.ensure_local_blitz_current!(
               path: tmp_root,
               stamp_path: stamp_path,
               compile_fun: compile_fun
             ) == :compiled

      assert_receive {:compiled, ^tmp_root}

      assert Ci.ensure_local_blitz_current!(
               path: tmp_root,
               stamp_path: stamp_path,
               compile_fun: compile_fun
             ) == :current

      refute_receive {:compiled, _}

      File.write!(Path.join(tmp_root, ".blitz/state"), "generated\n")
      File.write!(Path.join(tmp_root, "_build/state"), "generated\n")

      assert Ci.ensure_local_blitz_current!(
               path: tmp_root,
               stamp_path: stamp_path,
               compile_fun: compile_fun
             ) == :current

      refute_receive {:compiled, _}

      File.write!(
        Path.join(tmp_root, "lib/demo.ex"),
        "defmodule Demo do\n  def changed?, do: true\nend\n"
      )

      assert Ci.ensure_local_blitz_current!(
               path: tmp_root,
               stamp_path: stamp_path,
               compile_fun: compile_fun
             ) == :compiled

      assert_receive {:compiled, ^tmp_root}
    after
      File.rm_rf!(tmp_root)
    end
  end

  test "workspace root uses released Weld and the repo-local publication contract" do
    deps = MixProject.project()[:deps]

    assert {:weld, "~> 0.8.2", only: [:dev, :test], runtime: false} in deps,
           "workspace root must depend directly on the released Weld line"

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

  test "weld contract keeps the published docs surface package-facing" do
    docs =
      load_weld_contract!().artifact()
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

  test "platform carries splode directly so monolith test support does not force a conflicting test-only dep" do
    [{platform_mix_project, _binary}] = Code.require_file("core/platform/mix.exs", repo_root())

    deps = platform_mix_project.project()[:deps]

    assert Enum.any?(deps, fn
             {:splode, "~> 0.3.0"} -> true
             {:splode, "~> 0.3.0", opts} when is_list(opts) -> opts[:only] in [nil, []]
             _ -> false
           end),
           "core/platform must carry a non-test-only splode dep so release.prepare keeps the monolith dependency graph coherent"
  end

  test "workspace isolation clears SSL key logging for monorepo verification tasks" do
    isolation = MixProject.project()[:blitz_workspace][:isolation]

    assert "SSLKEYLOGFILE" in isolation[:unset_env],
           "blitz workspace isolation must unset SSLKEYLOGFILE so Req-backed tasks do not fail on read-only home mounts"
  end

  test "workspace root carries the canonical dependency source bootstrap" do
    helper_path = Path.join(repo_root(), "build_support/dependency_sources.exs")
    config_path = Path.join(repo_root(), "build_support/dependency_sources.config.exs")
    template_path = Path.expand("../weld/priv/templates/dependency_sources.exs", repo_root())

    assert File.exists?(helper_path), "missing canonical dependency source helper"
    assert File.read!(helper_path) == File.read!(template_path)
    assert File.exists?(config_path), "missing dependency source manifest"

    assert File.read!(Path.join(repo_root(), ".gitignore")) =~ ".dependency_sources.local.exs"
  end

  test "workspace root resolves external dependencies through the dependency source manifest" do
    resolver_source =
      repo_root()
      |> Path.join("build_support/dependency_resolver.exs")
      |> File.read!()

    assert String.contains?(
             resolver_source,
             "def pristine(opts \\\\ []), do: external_dep(:pristine, opts)"
           ),
           "root Pristine resolver must delegate source selection to DependencySources"

    refute String.contains?(resolver_source, ~S[local_root_path(]),
           "root external dependency resolver must not keep one-off sibling path logic"

    refute String.contains?(resolver_source, ~S[System.get_env]),
           "root Pristine resolver must not depend on environment-variable path selectors"

    {manifest, _binding} =
      repo_root()
      |> Path.join("build_support/dependency_sources.config.exs")
      |> Code.eval_file()

    deps = Map.fetch!(manifest, :deps)

    assert deps.pristine.hex == "~> 0.2.1",
           "root Pristine resolver must keep a Hex fallback for publishable contexts"

    assert deps.ground_plane_persistence_policy.github == %{
             repo: "nshkrdotcom/ground_plane",
             branch: "main",
             subdir: "core/persistence_policy"
           }

    assert deps.inference.github == %{
             repo: "nshkrdotcom/inference",
             branch: "main",
             subdir: "apps/inference"
           }

    assert deps.execution_plane.github == %{
             repo: "nshkrdotcom/execution_plane",
             branch: "main",
             subdir: "core/execution_plane"
           }

    assert deps.execution_plane_jsonrpc.github == %{
             repo: "nshkrdotcom/execution_plane",
             branch: "main",
             subdir: "protocols/execution_plane_jsonrpc"
           }

    pristine_runtime_path = Path.expand("../pristine/apps/pristine_runtime", repo_root())

    case DependencyResolver.pristine(runtime: false) do
      {:pristine, opts} ->
        assert Keyword.fetch!(opts, :path) == pristine_runtime_path
        assert Keyword.fetch!(opts, :runtime) == false

      {:pristine, "~> 0.2.1", opts} ->
        refute File.dir?(pristine_runtime_path),
               "expected sibling Pristine runtime path to exist at #{pristine_runtime_path}"

        assert Keyword.fetch!(opts, :runtime) == false
    end
  end

  test "unpublished runtime packages use git fallbacks for downstream Weld consumers" do
    {manifest, _binding} =
      repo_root()
      |> Path.join("build_support/dependency_sources.config.exs")
      |> Code.eval_file()

    deps = Map.fetch!(manifest, :deps)

    assert deps.inference.github.repo == "nshkrdotcom/inference",
           "Inference fallback must use its source repository instead of the package registry"

    assert deps.inference.github.subdir == "apps/inference",
           "Inference fallback must point at its package subdirectory"

    assert deps.execution_plane.github.repo == "nshkrdotcom/execution_plane",
           "Execution Plane fallback must use its source repository instead of the package registry"

    assert deps.execution_plane.github.subdir == "core/execution_plane",
           "Execution Plane fallback must point at its package subdirectory"

    assert deps.execution_plane_jsonrpc.github.repo == "nshkrdotcom/execution_plane",
           "Execution Plane JSON-RPC fallback must use its source repository instead of the package registry"

    assert deps.execution_plane_jsonrpc.github.subdir == "protocols/execution_plane_jsonrpc",
           "Execution Plane JSON-RPC fallback must point at its package subdirectory"
  end

  test "workspace internal Git fallbacks use the canonical source repository" do
    resolver_source =
      repo_root()
      |> Path.join("build_support/dependency_resolver.exs")
      |> File.read!()

    assert String.contains?(resolver_source, ~S[github: "nshkrdotcom/jido_integration"]),
           "internal package fallbacks must stay on the canonical source repo"

    refute String.contains?(resolver_source, ~S[github: "agentjido/jido_integration"]),
           "internal package fallbacks must not fetch stale package sources"
  end

  test "workspace root runtime and tooling files avoid direct OS env APIs" do
    forbidden_calls = [
      "System.get_env(",
      "System.fetch_env(",
      "System.fetch_env!(",
      "System.put_env(",
      "System.delete_env(",
      "System.get_envs("
    ]

    for relative_path <- [
          "mix.exs",
          "lib/jido/integration/toolchain.ex",
          "lib/jido/integration/workspace/monorepo_runner.ex",
          "lib/jido/integration/workspace/postgres_preflight.ex",
          "lib/mix/tasks/jido.conformance.ex"
        ] do
      source = File.read!(Path.join(repo_root(), relative_path))

      refute Enum.any?(forbidden_calls, &String.contains?(source, &1)),
             "#{relative_path} must use materialized runtime config or explicit command env instead of direct OS env APIs"
    end
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

  test "workspace scope is explicit about the active package families" do
    assert WorkspaceContract.active_project_globs() == [
             ".",
             "core/*",
             "scaffolds/*",
             "connectors/*",
             "apps/devops_incident_response",
             "apps/inference_ops"
           ]

    refute File.dir?(Path.join(repo_root(), "bridges"))
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
        assert String.contains?(mix_exs, snippet),
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
    asm_runtime_bridge_mix =
      repo_root()
      |> Path.join("core/asm_runtime_bridge/mix.exs")
      |> File.read!()
      |> normalize_whitespace()

    assert String.contains?(
             asm_runtime_bridge_mix,
             "Code.require_file(\"../../build_support/dependency_resolver.exs\", __DIR__)"
           ),
           "core/asm_runtime_bridge/mix.exs must load the shared dependency resolver"

    for required_snippet <- [
          "DependencyResolver.agent_session_manager(env: :dev)"
        ] do
      assert String.contains?(asm_runtime_bridge_mix, required_snippet),
             "core/asm_runtime_bridge/mix.exs is missing #{required_snippet}"
    end

    refute String.contains?(asm_runtime_bridge_mix, "DependencyResolver.boundary("),
           "core/asm_runtime_bridge/mix.exs must not depend on agent_session_manager/vendor/boundary"

    control_plane_mix =
      repo_root()
      |> Path.join("core/control_plane/mix.exs")
      |> File.read!()
      |> normalize_whitespace()

    refute String.contains?(control_plane_mix, "agent_session_manager_path ="),
           "core/control_plane/mix.exs must not own agent_session_manager directly"

    refute String.contains?(control_plane_mix, "{:agent_session_manager,"),
           "core/control_plane/mix.exs must route ASM through asm_runtime_bridge instead of depending on it directly"

    refute String.contains?(control_plane_mix, "{:boundary,"),
           "core/control_plane/mix.exs must not expose ASM's boundary compiler directly"
  end

  test "control_plane reaches non-direct runtimes through the runtime router package" do
    control_plane_mix =
      repo_root()
      |> Path.join("core/control_plane/mix.exs")
      |> File.read!()
      |> normalize_whitespace()

    assert String.contains?(
             control_plane_mix,
             "DependencyResolver.jido_integration_v2_runtime_router(only: :test)"
           ),
           "core/control_plane/mix.exs must keep the runtime router behind a test-only package dependency"

    refute String.contains?(control_plane_mix, "DependencyResolver.jido_session()"),
           "core/control_plane/mix.exs must not depend on the session runtime package directly"

    refute String.contains?(control_plane_mix, "../../../jido_session"),
           "core/control_plane/mix.exs must not depend on a sibling jido_session repo checkout"
  end

  defp child_package_roots do
    repo_root()
    |> Path.join("{core,bridges,connectors,apps,scaffolds}/*/mix.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.dirname/1)
    |> Enum.sort()
  end

  defp child_package_mix_paths do
    repo_root()
    |> Path.join("{core,bridges,connectors,apps,scaffolds}/*/mix.exs")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp repo_root, do: Path.expand("../..", __DIR__)

  defp load_weld_contract! do
    Code.require_file("build_support/weld.exs", repo_root())
    Jido.Integration.Build.WeldContract
  end

  defp normalize_whitespace(text), do: text |> String.split() |> Enum.join(" ")
end
