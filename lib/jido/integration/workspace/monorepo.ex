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
      ensure_project_deps!(project_path, task)
      run_project!(project_path, task, mix_args(task, extra_args))
    end)
  end

  @spec command_env(String.t(), task_name()) :: [{String.t(), String.t()}]
  def command_env(project_path, task) do
    project_root = Path.expand(project_path, root_dir())

    [
      {"MIX_DEPS_PATH", Path.join(project_root, "deps")},
      {"MIX_BUILD_PATH", Path.join(project_root, "_build/#{mix_env(task)}")},
      {"MIX_LOCKFILE", Path.join(project_root, "mix.lock")}
    ]
  end

  defp ensure_project_deps!(_project_path, :deps_get), do: :ok

  defp ensure_project_deps!(project_path, _task) do
    project_root = Path.expand(project_path, root_dir())

    if File.exists?(Path.join(project_root, "mix.lock")) and
         not File.dir?(Path.join(project_root, "deps")) do
      run_project!(project_path, :deps_get, mix_args(:deps_get, []))
    else
      :ok
    end
  end

  defp run_project!(project_path, task, args) do
    IO.puts("==> #{project_path}: mix #{Enum.join(args, " ")}")

    project_root = Path.expand(project_path, root_dir())

    case System.cmd("mix", args,
           cd: project_root,
           env: command_env(project_path, task),
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {_, exit_code} ->
        Mix.raise("command failed in #{project_path} with exit code #{exit_code}")
    end
  end

  defp mix_env(:test), do: "test"
  defp mix_env(_task), do: System.get_env("MIX_ENV", "dev")
end
