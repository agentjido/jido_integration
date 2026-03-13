defmodule Mix.Tasks.Monorepo.Test do
  use Mix.Task

  @moduledoc false

  alias Jido.Integration.V2.Monorepo

  @shortdoc "Run tests for the root app and every child package"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:test, args)
  end
end
