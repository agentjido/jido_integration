defmodule Jido.Integration.V2.Connectors.Notion.Build.DependencyResolver do
  @moduledoc false

  @project_root Path.expand("..", __DIR__)

  def notion_sdk(opts \\ []) do
    case sibling_path("../../../notion_sdk") do
      nil -> {:notion_sdk, "~> 0.2.1", opts}
      path -> {:notion_sdk, Keyword.merge([path: path], opts)}
    end
  end

  defp sibling_path(relative_path) do
    path = Path.expand(relative_path, @project_root)
    if File.dir?(path), do: path
  end
end
