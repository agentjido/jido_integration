defmodule Mix.Tasks.Monorepo.Credo do
  use Mix.Task

  @moduledoc false

  alias Jido.Integration.V2.Monorepo

  @shortdoc "Run Credo for the root app and every child package"

  @impl Mix.Task
  def run(args) do
    Monorepo.run!(:credo, args)
  end
end
