defmodule Jido.Integration.Build.WorkspaceContract do
  @moduledoc false

  @active_project_globs [
    ".",
    "core/*",
    "connectors/*",
    "apps/*"
  ]

  @legacy_project_roots [
    "bridges/boundary_bridge"
  ]

  def active_project_globs, do: @active_project_globs

  def legacy_project_roots, do: @legacy_project_roots
end
