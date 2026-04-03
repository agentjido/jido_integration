defmodule Jido.Integration.V2.Connectors.Linear.Build.DependencyResolver do
  @moduledoc false

  @project_root Path.expand("..", __DIR__)

  def linear_sdk(opts \\ []) do
    case workspace_path(["../../../linear_sdk"]) do
      nil -> {:linear_sdk, "~> 0.2.0", opts}
      path -> {:linear_sdk, Keyword.merge([path: path], opts)}
    end
  end

  def prismatic(opts \\ []) do
    case workspace_path(["../../../prismatic/apps/prismatic_runtime"]) do
      nil -> {:prismatic, "~> 0.2.0", opts}
      path -> {:prismatic, Keyword.merge([path: path], opts)}
    end
  end

  defp workspace_path(local_paths) do
    if prefer_workspace_paths?() do
      Enum.find_value(local_paths, &existing_path/1)
    end
  end

  defp prefer_workspace_paths? do
    not Enum.member?(Path.split(@project_root), "deps")
  end

  defp existing_path(relative_path) do
    expanded_path = Path.expand(relative_path, @project_root)

    if File.dir?(expanded_path) do
      expanded_path
    end
  end
end
