defmodule Jido.Integration.Workspace.PackageSurfaceTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Workspace.MixProject

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

  test "packages that compile agent_session_manager expose boundary explicitly" do
    for relative_path <- ["core/control_plane/mix.exs", "core/runtime_asm_bridge/mix.exs"] do
      mix_exs = repo_root() |> Path.join(relative_path) |> File.read!()

      assert mix_exs =~ "{:agent_session_manager, path: \"../../../agent_session_manager\"}"

      assert mix_exs =~
               "{:boundary, path: \"../../../agent_session_manager/vendor/boundary\"",
             "#{relative_path} must expose boundary explicitly so isolated workspace builds can compile ASM"
    end
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
end
