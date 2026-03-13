defmodule Jido.Integration.Runtime.Persistence do
  @moduledoc false

  def default_path(prefix, opts) do
    dir = Keyword.get(opts, :dir, Path.join(System.tmp_dir!(), "jido_integration"))
    file = Keyword.get(opts, :file, "#{prefix}-#{suffix(Keyword.get(opts, :name))}.bin")
    Path.join(dir, file)
  end

  def load(path, default) do
    with {:ok, binary} <- File.read(path),
         {:ok, state} <- decode(binary) do
      state
    else
      _ -> default
    end
  end

  def persist(path, state) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, :erlang.term_to_binary(state))
    :ok
  end

  def now_ms, do: System.system_time(:millisecond)

  defp decode(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    _ -> {:error, :invalid}
  end

  defp suffix(nil), do: Integer.to_string(System.unique_integer([:positive]))
  defp suffix(name) when is_atom(name), do: Atom.to_string(name)
  defp suffix(name) when is_binary(name), do: name
  defp suffix(other), do: inspect(other)
end
