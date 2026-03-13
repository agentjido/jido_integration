defmodule Mix.Tasks.Monorepo.Docs do
  use Mix.Task

  @moduledoc """
  Build docs for the workspace root and every child project.
  """

  alias Jido.Integration.Workspace.Monorepo

  @shortdoc "Build docs for the root app and every child package"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:docs, args)
  end
end
