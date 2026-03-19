defmodule Jido.Integration.Workspace.Monorepo do
  @moduledoc """
  Tooling-root monorepo helper for running standard Mix tasks across the
  workspace root and every child project in isolation.
  """

  alias Blitz

  @project_globs [
    "core/*",
    "connectors/*",
    "apps/*"
  ]

  @max_concurrency_env "JIDO_MONOREPO_MAX_CONCURRENCY"
  @test_database_base_env "JIDO_INTEGRATION_V2_DB_BASE_NAME"
  @test_database_env "JIDO_INTEGRATION_V2_DB_NAME"
  @default_test_database "jido_integration_v2_test"
  @max_postgres_identifier_bytes 63

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
    {task_args, runner_opts} = split_runner_args(extra_args)
    runner_opts = Keyword.put_new(runner_opts, :max_concurrency, default_max_concurrency(task))

    task
    |> pending_dep_commands()
    |> run_commands!(runner_opts)

    task
    |> project_commands(task_args)
    |> run_commands!(runner_opts)
  end

  @spec command_env(String.t(), task_name()) :: [{String.t(), String.t()}]
  def command_env(project_path, task) do
    project_root = Path.expand(project_path, root_dir())

    [
      {"MIX_DEPS_PATH", Path.join(project_root, "deps")},
      {"MIX_BUILD_PATH", Path.join(project_root, "_build/#{mix_env(task)}")},
      {"MIX_LOCKFILE", Path.join(project_root, "mix.lock")}
    ] ++ sanitized_hex_env(project_root) ++ test_command_env(project_path, task)
  end

  @spec test_database_name(String.t()) :: String.t()
  def test_database_name(project_path) do
    base_name =
      System.get_env(
        @test_database_base_env,
        System.get_env(@test_database_env, @default_test_database)
      )

    suffix = project_test_database_suffix(project_path)
    separator_size = 1
    max_base_bytes = max(@max_postgres_identifier_bytes - byte_size(suffix) - separator_size, 1)

    base_name
    |> binary_part(0, min(byte_size(base_name), max_base_bytes))
    |> String.trim_trailing("_")
    |> then(fn
      "" -> suffix
      truncated_base -> "#{truncated_base}_#{suffix}"
    end)
  end

  @spec split_runner_args([String.t()]) :: {[String.t()], keyword()}
  def split_runner_args(args) do
    {task_args, max_concurrency} = do_split_runner_args(args, [], nil)
    runner_opts = if max_concurrency, do: [max_concurrency: max_concurrency], else: []

    {Enum.reverse(task_args), runner_opts}
  end

  defp do_split_runner_args([], task_args, max_concurrency) do
    {task_args, max_concurrency}
  end

  defp do_split_runner_args(["--max-concurrency", value | rest], task_args, _max_concurrency) do
    do_split_runner_args(rest, task_args, parse_max_concurrency!(value))
  end

  defp do_split_runner_args(
         [<<"--max-concurrency=", value::binary>> | rest],
         task_args,
         _max_concurrency
       ) do
    do_split_runner_args(rest, task_args, parse_max_concurrency!(value))
  end

  defp do_split_runner_args(["-j", value | rest], task_args, _max_concurrency) do
    do_split_runner_args(rest, task_args, parse_max_concurrency!(value))
  end

  defp do_split_runner_args([arg | rest], task_args, max_concurrency) do
    do_split_runner_args(rest, [arg | task_args], max_concurrency)
  end

  defp test_command_env(project_path, :test) do
    base_name =
      System.get_env(
        @test_database_base_env,
        System.get_env(@test_database_env, @default_test_database)
      )

    [
      {@test_database_base_env, base_name},
      {@test_database_env, test_database_name(project_path)}
    ]
  end

  defp test_command_env(_project_path, _task), do: []

  defp pending_dep_commands(:deps_get), do: []

  defp pending_dep_commands(_task) do
    project_paths()
    |> Enum.filter(&deps_missing?/1)
    |> Enum.map(&project_command(&1, :deps_get, []))
  end

  defp project_commands(task, extra_args) do
    Enum.map(project_paths(), &project_command(&1, task, extra_args))
  end

  defp project_command(project_path, task, extra_args) do
    Blitz.command(
      id: project_path,
      command: "mix",
      args: mix_args(task, extra_args),
      cd: Path.expand(project_path, root_dir()),
      env: command_env(project_path, task)
    )
  end

  defp deps_missing?(project_path) do
    project_root = Path.expand(project_path, root_dir())

    File.exists?(Path.join(project_root, "mix.lock")) and
      not File.dir?(Path.join(project_root, "deps"))
  end

  defp run_commands!([], _runner_opts), do: :ok

  defp run_commands!(commands, runner_opts) do
    Blitz.run!(commands, runner_opts)
    :ok
  end

  defp parse_max_concurrency!(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 ->
        parsed

      _ ->
        Mix.raise("expected --max-concurrency to be a positive integer, got: #{inspect(value)}")
    end
  end

  defp default_max_concurrency(task) do
    case System.get_env(@max_concurrency_env) do
      nil ->
        task
        |> task_max_concurrency_cap()
        |> min(System.schedulers_online())

      value ->
        parse_max_concurrency!(value)
    end
  end

  defp task_max_concurrency_cap(:deps_get), do: 6
  defp task_max_concurrency_cap(:format), do: 8
  defp task_max_concurrency_cap(:compile), do: 4
  defp task_max_concurrency_cap(:test), do: 4
  defp task_max_concurrency_cap(:credo), do: 4
  defp task_max_concurrency_cap(:dialyzer), do: 2
  defp task_max_concurrency_cap(:docs), do: 2

  defp mix_env(:test), do: "test"
  defp mix_env(_task), do: System.get_env("MIX_ENV", "dev")

  defp sanitized_hex_env(project_root) do
    [
      {"HEX_HOME", Path.join(project_root, "_build/hex")},
      {"HEX_API_KEY", nil}
    ]
  end

  defp project_test_database_suffix(project_path) do
    slug =
      project_path
      |> String.replace(".", "workspace")
      |> String.replace(~r/[^a-zA-Z0-9]+/u, "_")
      |> String.trim("_")
      |> String.downcase()

    hash =
      :sha256
      |> :crypto.hash(project_path)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 8)

    "#{slug}_#{hash}"
  end
end
