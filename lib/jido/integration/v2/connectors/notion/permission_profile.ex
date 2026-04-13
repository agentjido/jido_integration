defmodule Jido.Integration.V2.Connectors.Notion.PermissionProfile do
  @moduledoc false

  @profiles %{
    content_publishing: [
      "notion.identity.self",
      "notion.content.read",
      "notion.content.insert",
      "notion.content.update",
      "notion.comment.insert"
    ],
    workspace_read: [
      "notion.identity.self",
      "notion.user.read",
      "notion.content.read",
      "notion.comment.read"
    ],
    full_workspace: [
      "notion.identity.self",
      "notion.user.read",
      "notion.content.read",
      "notion.content.insert",
      "notion.content.update",
      "notion.comment.read",
      "notion.comment.insert",
      "notion.file_upload.write"
    ]
  }

  @spec default_profile() :: atom()
  def default_profile, do: :content_publishing

  @spec scopes(atom()) :: [String.t()]
  def scopes(profile) when is_atom(profile) do
    Map.fetch!(@profiles, profile)
  end

  @spec fetch(atom()) :: {:ok, [String.t()]} | :error
  def fetch(profile) when is_atom(profile) do
    case Map.fetch(@profiles, profile) do
      {:ok, scopes} -> {:ok, scopes}
      :error -> :error
    end
  end

  @spec names() :: [atom()]
  def names, do: Map.keys(@profiles)
end
