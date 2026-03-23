defmodule Mix.Tasks.Workspace.Docs do
  use Mix.Task
  @moduledoc false

  alias Jido.Integration.Workspace.MonorepoRunner

  @shortdoc "Run the monorepo docs stage through the workspace mix wrapper"

  @impl Mix.Task
  def run(args), do: MonorepoRunner.run!(:docs, args)
end
