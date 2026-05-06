defmodule Mix.Tasks.Workspace.Impact.Ci do
  use Mix.Task
  @moduledoc false

  alias Blitz.{Command, MixWorkspace}
  alias Blitz.MixWorkspace.Impact
  alias Jido.Integration.Workspace.MonorepoRunner

  @shortdoc "Run impact-aware monorepo CI through Blitz test state"

  @ci_stages [
    {:deps_get, []},
    {:format, ["--check-formatted"]},
    {:compile, []},
    {:test, []},
    {:credo, ["--strict"]},
    {:dialyzer, []},
    {:docs, []}
  ]

  @impact_policy [
    workspace_invalidators: [
      "build_support/dependency_resolver.exs",
      "build_support/workspace_contract.exs"
    ],
    aggregate_docs_projects: [],
    test_dependency_fanout: :source_only,
    deps_get_lockfile_self_invalidation: false
  ]

  def impact_policy, do: @impact_policy

  @fingerprint_excluded_segments [".git", ".blitz", "_build", "deps", "doc"]

  @impl Mix.Task
  def run(args) do
    ensure_local_blitz_current!()

    {opts, extra_args, invalid} =
      OptionParser.parse(args,
        strict: [
          dry_run: :boolean,
          force: :boolean,
          explain: :boolean,
          base: :string,
          head: :string,
          store_dir: :string,
          max_concurrency: :integer
        ],
        aliases: [f: :force, j: :max_concurrency]
      )

    validate_invalid!(invalid)

    workspace = MixWorkspace.load!()
    mix_command = MonorepoRunner.mix_command!(workspace)

    impact_opts =
      opts
      |> normalize_opts()
      |> Keyword.put(:command_mapper, &rewrite_command(&1, mix_command))
      |> Keyword.put(:impact_policy, impact_policy())

    runner_args = runner_args(opts)

    Impact.run_many!(workspace, ci_task_specs(workspace, runner_args ++ extra_args), impact_opts)
  after
    Mix.Task.reenable("workspace.impact.ci")
  end

  def ensure_local_blitz_current!(opts \\ []) do
    path = Keyword.get(opts, :path) || local_blitz_dep_path()

    cond do
      is_nil(path) ->
        :current

      not File.dir?(path) ->
        :current

      true ->
        stamp_path = Keyword.get(opts, :stamp_path, local_blitz_stamp_path())
        compile_fun = Keyword.get(opts, :compile_fun, &compile_local_blitz!/1)
        fingerprint = local_blitz_source_fingerprint(path)

        case File.read(stamp_path) do
          {:ok, ^fingerprint} ->
            :current

          _other ->
            compile_fun.(path)
            File.mkdir_p!(Path.dirname(stamp_path))
            File.write!(stamp_path, fingerprint)
            :compiled
        end
    end
  end

  def local_blitz_dep_path(project_config \\ Mix.Project.config()) do
    project_config
    |> Keyword.get(:deps, [])
    |> Enum.find_value(fn
      {:blitz, opts} when is_list(opts) ->
        Keyword.get(opts, :path)

      {:blitz, _requirement, opts} when is_list(opts) ->
        Keyword.get(opts, :path)

      _other ->
        nil
    end)
    |> case do
      nil -> nil
      path -> Path.expand(path, project_root(project_config))
    end
  end

  def local_blitz_source_fingerprint(path) do
    root = Path.expand(path)

    entries =
      root
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, root))
      |> Enum.reject(&fingerprint_excluded?/1)
      |> Enum.sort()
      |> Enum.map(fn relative_path ->
        absolute_path = Path.join(root, relative_path)

        %{
          path: relative_path,
          hash: :crypto.hash(:sha256, File.read!(absolute_path)) |> Base.encode16(case: :lower)
        }
      end)

    :crypto.hash(:sha256, :erlang.term_to_binary(entries))
    |> Base.encode16(case: :lower)
  end

  defp ci_task_specs(workspace, extra_args) do
    Enum.flat_map(@ci_stages, fn
      {:test, stage_args} ->
        args = stage_args ++ extra_args

        [
          {:test, args, [only_projects: MixWorkspace.package_paths(workspace)]},
          {:test, args, [only_projects: ["."]]}
        ]

      {task, stage_args} ->
        [{task, stage_args ++ extra_args, []}]
    end)
  end

  defp runner_args(opts) do
    case Keyword.get(opts, :max_concurrency) do
      nil -> []
      value -> ["--max-concurrency", Integer.to_string(value)]
    end
  end

  defp normalize_opts(opts) do
    opts
    |> Keyword.delete(:max_concurrency)
    |> Keyword.put_new(:dry_run, false)
    |> Keyword.put_new(:force, false)
  end

  defp rewrite_command(%Command{} = command, mix_command) do
    %Command{command | command: mix_command}
  end

  defp validate_invalid!([]), do: :ok

  defp validate_invalid!(invalid) do
    Mix.raise("Invalid options: #{inspect(invalid)}")
  end

  defp compile_local_blitz!(_path) do
    Mix.Task.reenable("deps.compile")
    Mix.Task.run("deps.compile", ["blitz", "--force"])
    :ok
  end

  defp local_blitz_stamp_path do
    Path.join(Mix.Project.build_path(), ".blitz_local_source_fingerprint")
  end

  defp project_root(project_config) do
    case Keyword.get(project_config, :blitz_workspace) do
      workspace when is_list(workspace) ->
        Keyword.get(workspace, :root) || Path.dirname(Mix.Project.project_file())

      _other ->
        Path.dirname(Mix.Project.project_file())
    end
  end

  defp fingerprint_excluded?(relative_path) do
    relative_path
    |> Path.split()
    |> Enum.any?(&(&1 in @fingerprint_excluded_segments))
  end
end
