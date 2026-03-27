defmodule Jido.Integration.V2.Connectors.Notion.Build.DependencyResolver do
  @moduledoc false

  @project_root Path.expand("..", __DIR__)
  @pristine_ref "674df61e5e2ab8c73927c75fb9b16a603301f89f"
  @notion_sdk_ref "4e8d5d96795c415385a03b8388113357d9ee8f3d"

  def pristine_runtime(opts \\ []) do
    resolve(
      :pristine,
      ["../../../pristine/apps/pristine_runtime"],
      [github: "nshkrdotcom/pristine", ref: @pristine_ref, subdir: "apps/pristine_runtime"],
      opts
    )
  end

  def notion_sdk(opts \\ []) do
    resolve(
      :notion_sdk,
      ["../../../notion_sdk"],
      [github: "nshkrdotcom/notion_sdk", ref: @notion_sdk_ref],
      opts
    )
  end

  defp resolve(app, local_paths, fallback_opts, opts) do
    case Enum.find_value(local_paths, &existing_path/1) do
      nil -> {app, Keyword.merge(fallback_opts, opts)}
      path -> {app, Keyword.merge([path: path], opts)}
    end
  end

  defp existing_path(relative_path) do
    expanded_path = Path.expand(relative_path, @project_root)

    if File.dir?(expanded_path) do
      expanded_path
    end
  end
end
