defmodule Mix.Tasks.Monorepo.Docs do
  use Mix.Task

  @moduledoc """
  Build docs for the workspace root and every child project in parallel.
  """

  alias Jido.Integration.Workspace.Monorepo

  @shortdoc "Build docs for the root app and every child package in parallel"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:docs, args)
  end
end
