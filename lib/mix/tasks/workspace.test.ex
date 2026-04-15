defmodule Mix.Tasks.Workspace.Test do
  use Mix.Task
  @moduledoc false

  alias Blitz.MixWorkspace
  alias Jido.Integration.Workspace.MonorepoRunner

  @shortdoc "Run the monorepo test stage through the workspace mix wrapper"

  @impl Mix.Task
  def run(args) do
    workspace = MixWorkspace.load!()
    MonorepoRunner.run_projects!(:test, args, MixWorkspace.package_paths(workspace))
    MonorepoRunner.run_root_task!(:test, args)
  end
end
