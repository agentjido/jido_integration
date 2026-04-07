defmodule Jido.Integration.V2.Connectors.GitHub.Build.DependencyResolver do
  @moduledoc false

  def github_ex(opts \\ []) do
    {:github_ex, "~> 0.1.0", opts}
  end
end
