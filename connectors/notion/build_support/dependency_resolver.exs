defmodule Jido.Integration.V2.Connectors.Notion.Build.DependencyResolver do
  @moduledoc false

  @project_root Path.expand("..", __DIR__)

  def pristine_runtime(opts \\ []) do
    resolve(
      :pristine,
      ["../../../pristine/apps/pristine_runtime"],
      [github: "nshkrdotcom/pristine", branch: "master", subdir: "apps/pristine_runtime"],
      opts
    )
  end

  def notion_sdk(opts \\ []) do
    case env_path("NOTION_SDK_PATH") do
      nil -> {:notion_sdk, "~> 0.2.0", opts}
      path -> {:notion_sdk, Keyword.merge([path: path], opts)}
    end
  end

  defp resolve(app, local_paths, fallback_opts, opts) do
    case workspace_path(local_paths) do
      nil -> {app, Keyword.merge(fallback_opts, opts)}
      path -> {app, Keyword.merge([path: path], opts)}
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

  defp env_path(env_var) do
    case System.get_env(env_var) do
      nil -> nil
      value -> existing_path(value)
    end
  end

  defp existing_path(nil), do: nil

  defp existing_path(relative_path) do
    expanded_path = Path.expand(relative_path, @project_root)

    if File.dir?(expanded_path) do
      expanded_path
    end
  end
end
