defmodule Jido.Integration.Workspace.MonorepoRunner do
  @moduledoc false

  import Bitwise

  alias Blitz.{Command, MixWorkspace}

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
    override_mix = Path.expand("/tmp/mix_override/bin/mix")

    candidate =
      System.get_env("PATH", "")
      |> String.split(":", trim: true)
      |> Enum.find_value(fn dir ->
        path = Path.join(dir, "mix")
        expanded = Path.expand(path)

        cond do
          not executable_file?(path) -> nil
          expanded == mix_wrapper -> nil
          expanded == override_mix -> nil
          true -> path
        end
      end)

    candidate || Mix.raise("Could not locate a system mix executable outside #{mix_wrapper}")
  end

  defp executable_file?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} -> band(mode, 0o111) != 0
      _other -> false
    end
  end
end
