defmodule Jido.Integration.V2.Connectors.Linear.Build.DependencyResolver do
  @moduledoc false

  @project_root Path.expand("..", __DIR__)

  def linear_sdk(opts \\ []) do
    case sibling_path("../../../linear_sdk") do
      nil -> {:linear_sdk, "~> 0.2.0", opts}
      path -> {:linear_sdk, Keyword.merge([path: path], opts)}
    end
  end

  def prismatic(opts \\ []) do
    case sibling_path("../../../prismatic/apps/prismatic_runtime") do
      nil -> {:prismatic, "~> 0.2.0", opts}
      path -> {:prismatic, Keyword.merge([path: path], opts)}
    end
  end

  defp sibling_path(relative_path) do
    path = Path.expand(relative_path, @project_root)
    if File.dir?(path), do: path
  end
end
