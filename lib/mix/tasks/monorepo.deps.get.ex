defmodule Mix.Tasks.Monorepo.Deps.Get do
  use Mix.Task

  @moduledoc """
  Fetch dependencies for the workspace root and every child project in parallel.
  """

  alias Jido.Integration.Workspace.Monorepo

  @shortdoc "Fetch deps for the root app and every child package in parallel"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:deps_get, args)
  end
end
