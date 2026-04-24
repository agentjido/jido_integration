defmodule Jido.Integration.V2.Connectors.GitHub.Build.DependencyResolver do
  @moduledoc false

  @project_root Path.expand("..", __DIR__)

  def github_ex(opts \\ []) do
    case sibling_path("../../../github_ex") do
      nil -> {:github_ex, "~> 0.1.1", opts}
      path -> {:github_ex, Keyword.merge([path: path], opts)}
    end
  end

  defp sibling_path(relative_path) do
    path = Path.expand(relative_path, @project_root)
    if File.dir?(path), do: path
  end
end
