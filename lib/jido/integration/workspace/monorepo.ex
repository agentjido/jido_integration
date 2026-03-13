defmodule Jido.Integration.Workspace.Monorepo do
  @moduledoc """
  Tooling-root monorepo helper for running standard Mix tasks across the
  workspace root and every child project in isolation.
  """

  @project_globs [
    "core/*",
    "connectors/*",
    "apps/*"
  ]

  @type task_name :: :deps_get | :compile | :test | :format | :credo | :dialyzer | :docs

  @spec root_dir() :: String.t()
  def root_dir do
    Path.expand("../../../../", __DIR__)
  end

  @spec project_paths() :: [String.t()]
  def project_paths do
    ["."]
    |> Kernel.++(package_paths())
  end

  @spec package_paths() :: [String.t()]
  def package_paths do
    root = root_dir()

    @project_globs
    |> Enum.flat_map(fn glob ->
      root
      |> Path.join(glob)
      |> Path.wildcard()
      |> Enum.filter(&File.regular?(Path.join(&1, "mix.exs")))
      |> Enum.sort()
    end)
    |> Enum.map(&Path.relative_to(&1, root))
  end

  @spec mix_args(task_name(), [String.t()]) :: [String.t()]
  def mix_args(:deps_get, extra_args), do: ["deps.get" | extra_args]
  def mix_args(:compile, extra_args), do: ["compile", "--warnings-as-errors" | extra_args]
  def mix_args(:test, extra_args), do: ["test" | extra_args]
  def mix_args(:format, extra_args), do: ["format" | extra_args]
  def mix_args(:credo, extra_args), do: ["credo" | extra_args]
  def mix_args(:dialyzer, extra_args), do: ["dialyzer", "--force-check" | extra_args]
  def mix_args(:docs, extra_args), do: ["docs" | extra_args]

  @spec run!(task_name(), [String.t()]) :: :ok
  def run!(task, extra_args \\ []) do
    Enum.each(project_paths(), fn project_path ->
      run_project!(project_path, mix_args(task, extra_args))
    end)
  end

  defp run_project!(project_path, args) do
    IO.puts("==> #{project_path}: mix #{Enum.join(args, " ")}")

    case System.cmd("mix", args,
           cd: Path.expand(project_path, root_dir()),
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {_, exit_code} ->
        Mix.raise("command failed in #{project_path} with exit code #{exit_code}")
    end
  end
end
