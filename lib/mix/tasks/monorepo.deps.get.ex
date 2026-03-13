defmodule Mix.Tasks.Monorepo.Deps.Get do
  use Mix.Task

  @moduledoc false

  alias Jido.Integration.V2.Monorepo

  @shortdoc "Fetch deps for the root app and every child package"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:deps_get, args)
  end
end
