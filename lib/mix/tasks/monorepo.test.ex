defmodule Mix.Tasks.Monorepo.Test do
  use Mix.Task

  @moduledoc """
  Run tests for the workspace root and every child project.
  """

  alias Jido.Integration.Workspace.Monorepo

  @shortdoc "Run tests for the root app and every child package"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:test, args)
  end
end
