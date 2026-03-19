defmodule Mix.Tasks.Monorepo.Compile do
  use Mix.Task

  @moduledoc """
  Compile the workspace root and every child project with warnings as errors in parallel.
  """

  alias Jido.Integration.Workspace.Monorepo

  @shortdoc "Compile the root app and every child package with warnings as errors in parallel"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:compile, args)
  end
end
