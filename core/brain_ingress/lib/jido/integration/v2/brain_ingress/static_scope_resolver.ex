defmodule Jido.Integration.V2.BrainIngress.StaticScopeResolver do
  @moduledoc """
  Minimal same-node resolver for logical workspace references.
  """

  @behaviour Jido.Integration.V2.BrainIngress.ScopeResolver

  @impl true
  def resolve(logical_workspace_ref, file_scope_ref, opts) do
    mapping = Keyword.get(opts, :mapping, %{})

    with {:ok, workspace_root} <- resolve_one(logical_workspace_ref, mapping),
         {:ok, file_scope} <- resolve_file_scope(file_scope_ref, workspace_root, mapping) do
      {:ok, %{workspace_root: workspace_root, file_scope: file_scope}}
    end
  end

  defp resolve_file_scope(nil, workspace_root, _mapping), do: {:ok, workspace_root}

  defp resolve_file_scope(file_scope_ref, _workspace_root, mapping),
    do: resolve_one(file_scope_ref, mapping)

  defp resolve_one(nil, _mapping), do: {:ok, nil}

  defp resolve_one(value, mapping) when is_binary(value) do
    cond do
      Path.type(value) == :absolute ->
        {:ok, value}

      String.starts_with?(value, "file://") ->
        {:ok, String.replace_prefix(value, "file://", "")}

      resolved = Map.get(mapping, value) ->
        {:ok, resolved}

      true ->
        {:error, {:scope_unresolvable, value}}
    end
  end
end
