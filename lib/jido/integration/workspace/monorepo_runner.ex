defmodule Jido.Integration.Workspace.MonorepoRunner do
  @moduledoc false

  import Bitwise

  alias Blitz.{Command, MixWorkspace}
  alias Jido.Integration.Toolchain

  @spec run!(atom(), [String.t()]) :: :ok
  def run!(task, args) when is_atom(task) and is_list(args) do
    workspace = MixWorkspace.load!()
    mix_command = mix_command!(workspace)

    workspace
    |> MixWorkspace.plan(task, args)
    |> Enum.each(fn stage ->
      stage.commands
      |> Enum.map(&rewrite_command(&1, mix_command))
      |> Blitz.run!(max_concurrency: stage.max_concurrency)
    end)

    :ok
  end

  @spec run_projects!(atom(), [String.t()], [String.t()]) :: :ok
  def run_projects!(task, args, project_paths)
      when is_atom(task) and is_list(args) and is_list(project_paths) do
    workspace = MixWorkspace.load!()
    mix_command = mix_command!(workspace)
    allowed_paths = MapSet.new(project_paths)

    workspace
    |> MixWorkspace.plan(task, args)
    |> Enum.each(fn stage ->
      commands =
        stage.commands
        |> Enum.filter(&MapSet.member?(allowed_paths, &1.id))
        |> Enum.map(&rewrite_command(&1, mix_command))

      if commands != [] do
        Blitz.run!(commands, max_concurrency: stage.max_concurrency)
      end
    end)

    :ok
  end

  @spec run_root_task!(atom(), [String.t()]) :: :ok
  def run_root_task!(task, args) when is_atom(task) and is_list(args) do
    workspace = MixWorkspace.load!()
    mix_command = mix_command!(workspace)
    {task_args, _runner_opts} = MixWorkspace.split_runner_args(args)
    mix_args = MixWorkspace.task_args(workspace, task, task_args)
    env = MixWorkspace.command_env(workspace, ".", task)

    case System.cmd(mix_command, mix_args,
           cd: workspace.root,
           env: env,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        Mix.raise("""
        root mix #{Enum.join(mix_args, " ")} failed with exit code #{exit_code}

        #{output}
        """)
    end
  end

  @doc false
  @spec mix_command!(map()) :: String.t()
  def mix_command!(workspace) do
    workspace_mix_command!(workspace)
  end

  defp rewrite_command(%Command{} = command, mix_command) do
    %Command{command | command: mix_command}
  end

  defp workspace_mix_command!(workspace) do
    mix_wrapper = Path.join(workspace.root, "bin/mix")

    if File.exists?(mix_wrapper) do
      resolve_system_mix!(mix_wrapper)
    else
      Mix.raise("workspace mix wrapper is missing: #{mix_wrapper}")
    end
  end

  defp resolve_system_mix!(mix_wrapper) do
    mix_wrapper = Path.expand(mix_wrapper)
    candidate = resolve_current_mix(mix_wrapper) || find_system_mix_in_path(mix_wrapper)

    candidate || Mix.raise("Could not locate a system mix executable outside #{mix_wrapper}")
  end

  defp resolve_current_mix(mix_wrapper) do
    candidate = Toolchain.mix_executable()

    if Path.expand(candidate) != mix_wrapper, do: candidate
  end

  defp find_system_mix_in_path(mix_wrapper) do
    System.get_env("PATH", "")
    |> String.split(":", trim: true)
    |> Enum.find_value(&path_mix_candidate(&1, mix_wrapper))
  end

  defp path_mix_candidate(dir, mix_wrapper) do
    path = Path.join(dir, "mix")

    if executable_file?(path) and Path.expand(path) != mix_wrapper do
      path
    end
  end

  defp executable_file?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} -> band(mode, 0o111) != 0
      _other -> false
    end
  end
end
