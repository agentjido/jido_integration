defmodule Mix.Tasks.Monorepo.Dialyzer do
  use Mix.Task

  @moduledoc """
  Run Dialyzer for the workspace root and every child project.
  """

  alias Jido.Integration.Workspace.Monorepo

  @shortdoc "Run Dialyzer for the root app and every child package"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:dialyzer, args)
  end
end
