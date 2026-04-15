defmodule Jido.Integration.Build.WorkspaceContract do
  @moduledoc false

  @active_app_projects [
    "apps/devops_incident_response",
    "apps/inference_ops"
  ]

  @active_project_globs [
    ".",
    "core/*",
    "connectors/*",
    @active_app_projects
  ]
  |> List.flatten()

  def active_project_globs, do: @active_project_globs
  def active_app_projects, do: @active_app_projects
end
