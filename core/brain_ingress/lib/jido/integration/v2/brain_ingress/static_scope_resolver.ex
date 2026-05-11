defmodule Jido.Integration.V2.BrainIngress.StaticScopeResolver do
  @moduledoc """
  Minimal same-node resolver for logical workspace references.
  """

  @behaviour Jido.Integration.V2.BrainIngress.ScopeResolver

  @impl true
  def resolve(logical_workspace_ref, file_scope_ref, opts) do
    mapping = Keyword.get(opts, :mapping, %{})

    with {:ok, raw_workspace_root} <- resolve_one(logical_workspace_ref, mapping),
         {:ok, raw_file_scope} <- resolve_file_scope(file_scope_ref, raw_workspace_root, mapping),
         workspace_root <- canonical_existing(raw_workspace_root),
         file_scope <- canonical_existing(raw_file_scope),
         :ok <- validate_scope(raw_workspace_root, workspace_root, raw_file_scope, file_scope) do
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

  defp validate_scope(nil, _workspace_root, nil, _file_scope), do: :ok
  defp validate_scope(nil, _workspace_root, _raw_file_scope, _file_scope), do: :ok
  defp validate_scope(_raw_workspace_root, _workspace_root, nil, _file_scope), do: :ok

  defp validate_scope(raw_workspace_root, workspace_root, raw_file_scope, file_scope) do
    raw_workspace_root = Path.expand(raw_workspace_root)
    raw_file_scope = Path.expand(raw_file_scope)

    cond do
      not under_or_equal?(raw_workspace_root, raw_file_scope) ->
        {:error,
         {:scope_outside_workspace_root,
          %{workspace_root: raw_workspace_root, file_scope: raw_file_scope}}}

      not under_or_equal?(workspace_root, file_scope) ->
        {:error,
         {:scope_symlink_escape, %{workspace_root: workspace_root, file_scope: file_scope}}}

      true ->
        :ok
    end
  end

  defp under_or_equal?(root, path) do
    path == root or String.starts_with?(path, root <> "/")
  end

  defp canonical_existing(nil), do: nil

  defp canonical_existing(path) do
    expanded = Path.expand(path)

    case Path.split(expanded) do
      [root | parts] -> resolve_parts(root, parts)
      [] -> expanded
    end
  end

  defp resolve_parts(current, []), do: current

  defp resolve_parts(current, [part | rest]) do
    candidate = Path.join(current, part)

    case File.lstat(candidate) do
      {:ok, %{type: :symlink}} ->
        case File.read_link(candidate) do
          {:ok, target} -> resolve_parts(Path.expand(target, current), rest)
          {:error, _reason} -> candidate
        end

      {:ok, _stat} ->
        resolve_parts(candidate, rest)

      {:error, _reason} ->
        Enum.reduce(rest, candidate, &Path.join(&2, &1))
    end
  end
end
