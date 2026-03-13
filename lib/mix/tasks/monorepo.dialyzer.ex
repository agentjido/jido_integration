defmodule Mix.Tasks.Monorepo.Dialyzer do
  use Mix.Task

  @moduledoc false

  alias Jido.Integration.V2.Monorepo

  @shortdoc "Run Dialyzer for the root app and every child package"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:dialyzer, args)
  end
end
