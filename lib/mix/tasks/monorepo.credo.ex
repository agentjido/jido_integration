defmodule Mix.Tasks.Monorepo.Credo do
  use Mix.Task

  @moduledoc """
  Run Credo for the workspace root and every child project.
  """

  alias Jido.Integration.Workspace.Monorepo

  @shortdoc "Run Credo for the root app and every child package"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:credo, args)
  end
end
