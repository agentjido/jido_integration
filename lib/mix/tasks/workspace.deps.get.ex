defmodule Mix.Tasks.Workspace.Deps.Get do
  use Mix.Task

  alias Jido.Integration.Workspace.MonorepoRunner

  @shortdoc "Run the monorepo deps-get stage through the workspace mix wrapper"

  @impl Mix.Task
  def run(args), do: MonorepoRunner.run!(:deps_get, args)
end
