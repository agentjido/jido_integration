defmodule Jido.Integration.V2.Connectors.GitHub.Build.DependencyResolver do
  @moduledoc false

  @project_root Path.expand("..", __DIR__)
  @pristine_ref "674df61e5e2ab8c73927c75fb9b16a603301f89f"
  @github_ex_ref "be827bad7169adf85656ebafccb7f4326cdce475"

  def pristine_runtime(opts \\ []) do
    resolve(
      :pristine,
      ["../../../pristine/apps/pristine_runtime"],
      [github: "nshkrdotcom/pristine", ref: @pristine_ref, subdir: "apps/pristine_runtime"],
      opts
    )
  end

  def github_ex(opts \\ []) do
    resolve(
      :github_ex,
      ["../../../github_ex"],
      [github: "nshkrdotcom/github_ex", ref: @github_ex_ref],
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
