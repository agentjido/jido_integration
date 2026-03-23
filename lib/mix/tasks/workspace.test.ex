defmodule Mix.Tasks.Workspace.Test do
  use Mix.Task

  alias Jido.Integration.Workspace.MonorepoRunner

  @shortdoc "Run the monorepo test stage through the workspace mix wrapper"

  @impl Mix.Task
  def run(args), do: MonorepoRunner.run!(:test, args)
end
