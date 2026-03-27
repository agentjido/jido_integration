defmodule Jido.Integration.Workspace.PackageSurfaceTest do
  use ExUnit.Case, async: true

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
    ~s(elixir: "~> 1.18"),
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
          :"mr.docs"
        ] do
      assert Keyword.has_key?(aliases, alias_name),
             "expected workspace alias #{inspect(alias_name)} to exist"
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

  test "Phase 6A bridge packages are absent from the workspace package graph" do
    for relative_path <- ["core/session_kernel", "core/stream_runtime"] do
      refute File.exists?(Path.join(repo_root(), relative_path)),
             "#{relative_path} must be deleted from the workspace"
    end
  end

  test "packages that compile agent_session_manager expose boundary explicitly" do
    runtime_asm_bridge_mix =
      repo_root()
      |> Path.join("core/runtime_asm_bridge/mix.exs")
      |> File.read!()
      |> normalize_whitespace()

    assert runtime_asm_bridge_mix =~
             "Code.require_file(\"../../build_support/dependency_resolver.exs\", __DIR__)",
           "core/runtime_asm_bridge/mix.exs must load the shared dependency resolver"

    for required_snippet <- [
          "DependencyResolver.agent_session_manager(env: :dev)",
          "DependencyResolver.boundary(only: [:dev, :test], runtime: false)"
        ] do
      assert runtime_asm_bridge_mix =~ required_snippet,
             "core/runtime_asm_bridge/mix.exs is missing #{required_snippet}"
    end

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

  test "control_plane takes jido_session from the in-repo session runtime package" do
    control_plane_mix =
      repo_root()
      |> Path.join("core/control_plane/mix.exs")
      |> File.read!()
      |> normalize_whitespace()

    assert control_plane_mix =~ "DependencyResolver.jido_session()",
           "core/control_plane/mix.exs must depend on the shared session runtime package through the dependency resolver"

    refute control_plane_mix =~ "../../../jido_session",
           "core/control_plane/mix.exs must not depend on a sibling jido_session repo checkout"
  end

  defp child_package_roots do
    repo_root()
    |> Path.join("{core,connectors,apps}/*/mix.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.dirname/1)
    |> Enum.sort()
  end

  defp child_package_mix_paths do
    repo_root()
    |> Path.join("{core,connectors,apps}/*/mix.exs")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp repo_root, do: Path.expand("../..", __DIR__)

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
