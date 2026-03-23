defmodule Mix.Tasks.Workspace.Compile do
  use Mix.Task
  @moduledoc false

  alias Jido.Integration.Workspace.MonorepoRunner

  @shortdoc "Run the monorepo compile stage through the workspace mix wrapper"

  @impl Mix.Task
  def run(args), do: MonorepoRunner.run!(:compile, args)
end
