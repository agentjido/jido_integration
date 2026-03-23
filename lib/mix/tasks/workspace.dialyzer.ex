defmodule Mix.Tasks.Workspace.Dialyzer do
  use Mix.Task

  alias Jido.Integration.Workspace.MonorepoRunner

  @shortdoc "Run the monorepo Dialyzer stage through the workspace mix wrapper"

  @impl Mix.Task
  def run(args), do: MonorepoRunner.run!(:dialyzer, args)
end
