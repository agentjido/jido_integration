defmodule Mix.Tasks.Monorepo.Format do
  use Mix.Task

  @moduledoc """
  Run `mix format` for the workspace root and every child project.
  """

  alias Jido.Integration.Workspace.Monorepo

  @shortdoc "Run mix format for the root app and every child package"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:format, args)
  end
end
