defmodule Mix.Tasks.Monorepo.Docs do
  use Mix.Task

  @moduledoc false

  alias Jido.Integration.V2.Monorepo

  @shortdoc "Build docs for the root app and every child package"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:docs, args)
  end
end
