defmodule Jido.Integration.Workspace.MonorepoRunner do
  @moduledoc false

  alias Blitz.{Command, MixWorkspace}

  @spec run!(atom(), [String.t()]) :: :ok
  def run!(task, args) when is_atom(task) and is_list(args) do
    workspace = MixWorkspace.load!()
    mix_command = workspace_mix_command!(workspace)

    workspace
    |> MixWorkspace.plan(task, args)
    |> Enum.each(fn stage ->
      stage.commands
      |> Enum.map(&rewrite_command(&1, mix_command))
      |> Blitz.run!(max_concurrency: stage.max_concurrency)
    end)

    :ok
  end

  defp rewrite_command(%Command{} = command, mix_command) do
    %Command{command | command: mix_command}
  end

  defp workspace_mix_command!(workspace) do
    mix_command = Path.join(workspace.root, "bin/mix")

    if File.exists?(mix_command) do
      mix_command
    else
      Mix.raise("workspace mix wrapper is missing: #{mix_command}")
    end
  end
end
