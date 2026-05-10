defmodule Jido.Integration.V2.Connectors.Notion.Build.DependencyResolver do
  @moduledoc false

  unless Code.ensure_loaded?(DependencySources) do
    Code.require_file("../../../build_support/dependency_sources.exs", __DIR__)
  end

  @repo_root Path.expand("../../..", __DIR__)

  def notion_sdk(opts \\ []),
    do: :notion_sdk |> DependencySources.dep(@repo_root, opts) |> expand_path_dep()

  defp expand_path_dep({app, opts}) when is_list(opts) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} -> {app, Keyword.put(opts, :path, Path.expand(path, @repo_root))}
      :error -> {app, opts}
    end
  end

  defp expand_path_dep(dep), do: dep
end
