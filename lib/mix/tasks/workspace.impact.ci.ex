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

  @impl Mix.Task
  def run(args) do
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
end
