defmodule Mix.Tasks.Workspace.Format do
  use Mix.Task

  alias Jido.Integration.Workspace.MonorepoRunner

  @shortdoc "Run the monorepo format stage through the workspace mix wrapper"

  @impl Mix.Task
  def run(args), do: MonorepoRunner.run!(:format, args)
end
