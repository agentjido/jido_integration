defmodule Mix.Tasks.Monorepo.Format do
  use Mix.Task

  @moduledoc false

  alias Jido.Integration.V2.Monorepo

  @shortdoc "Run mix format for the root app and every child package"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:format, args)
  end
end
