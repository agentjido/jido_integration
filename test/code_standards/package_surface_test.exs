defmodule Jido.Integration.Workspace.PackageSurfaceTest do
  use ExUnit.Case, async: false

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
          :"weld.release.track",
          :"weld.release.archive",
          :"release.prepare",
          :"release.track",
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

  test "shared dependency resolver prefers WELD_PATH over git and hex" do
    with_env(
      %{
        "WELD_PATH" => "../weld",
        "WELD_GIT_REF" => "deadbeef",
        "WELD_GIT_URL" => "https://example.test/ignored/weld.git"
      },
      fn ->
        assert {:weld, opts} = DependencyResolver.weld()

        assert Keyword.fetch!(opts, :path) == Path.expand("../weld", repo_root())
        refute Keyword.has_key?(opts, :git)
        refute Keyword.has_key?(opts, :ref)
      end
    )
  end

  test "shared dependency resolver uses the canonical weld git URL when only a ref is set" do
    with_env(
      %{
        "WELD_PATH" => "disabled",
        "WELD_GIT_REF" => "773ba79",
        "WELD_GIT_URL" => nil
      },
      fn ->
        assert {:weld, opts} = DependencyResolver.weld()

        assert Keyword.fetch!(opts, :git) == "https://github.com/nshkrdotcom/weld.git"
        assert Keyword.fetch!(opts, :ref) == "773ba79"
        refute Keyword.has_key?(opts, :path)
      end
    )
  end

  test "shared dependency resolver supports explicit weld git URLs" do
    with_env(
      %{
        "WELD_PATH" => "disabled",
        "WELD_GIT_REF" => "feedface",
        "WELD_GIT_URL" => "https://example.test/custom/weld.git"
      },
      fn ->
        assert {:weld, opts} = DependencyResolver.weld()

        assert Keyword.fetch!(opts, :git) == "https://example.test/custom/weld.git"
        assert Keyword.fetch!(opts, :ref) == "feedface"
        refute Keyword.has_key?(opts, :path)
      end
    )
  end

  test "shared dependency resolver falls back to Hex when weld overrides are disabled" do
    with_env(
      %{
        "WELD_PATH" => "disabled",
        "WELD_GIT_REF" => "disabled",
        "WELD_GIT_URL" => "disabled"
      },
      fn ->
        assert {:weld, requirement, opts} = DependencyResolver.weld()
        assert requirement == "~> 0.6.0"
        refute Keyword.has_key?(opts, :path)
        refute Keyword.has_key?(opts, :git)
        refute Keyword.has_key?(opts, :ref)
      end
    )
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
    asm_runtime_bridge_mix =
      repo_root()
      |> Path.join("core/asm_runtime_bridge/mix.exs")
      |> File.read!()
      |> normalize_whitespace()

    assert asm_runtime_bridge_mix =~
             "Code.require_file(\"../../build_support/dependency_resolver.exs\", __DIR__)",
           "core/asm_runtime_bridge/mix.exs must load the shared dependency resolver"

    for required_snippet <- [
          "DependencyResolver.agent_session_manager(env: :dev)"
        ] do
      assert asm_runtime_bridge_mix =~ required_snippet,
             "core/asm_runtime_bridge/mix.exs is missing #{required_snippet}"
    end

    refute asm_runtime_bridge_mix =~ "DependencyResolver.boundary(",
           "core/asm_runtime_bridge/mix.exs must not depend on agent_session_manager/vendor/boundary"

    control_plane_mix =
      repo_root()
      |> Path.join("core/control_plane/mix.exs")
      |> File.read!()
      |> normalize_whitespace()

    refute control_plane_mix =~ "agent_session_manager_path =",
           "core/control_plane/mix.exs must not own agent_session_manager directly"

    refute control_plane_mix =~ "{:agent_session_manager,",
           "core/control_plane/mix.exs must route ASM through asm_runtime_bridge instead of depending on it directly"

    refute control_plane_mix =~ "{:boundary,",
           "core/control_plane/mix.exs must not expose ASM's boundary compiler directly"
  end

  test "control_plane reaches non-direct runtimes through the runtime router package" do
    control_plane_mix =
      repo_root()
      |> Path.join("core/control_plane/mix.exs")
      |> File.read!()
      |> normalize_whitespace()

    assert control_plane_mix =~
             "DependencyResolver.jido_integration_v2_runtime_router(only: :test)",
           "core/control_plane/mix.exs must keep the runtime router behind a test-only package dependency"

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

  defp with_env(overrides, fun) do
    previous =
      overrides
      |> Map.keys()
      |> Map.new(fn key -> {key, System.get_env(key)} end)

    Enum.each(overrides, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)

    try do
      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end

  defp repo_root, do: Path.expand("../..", __DIR__)

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
