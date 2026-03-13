defmodule Mix.Tasks.Monorepo.Compile do
  use Mix.Task

  @moduledoc false

  alias Jido.Integration.V2.Monorepo

  @shortdoc "Compile the root app and every child package with warnings as errors"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:compile, args)
  end
end
