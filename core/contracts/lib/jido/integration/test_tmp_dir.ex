defmodule Jido.Integration.TestTmpDir do
  @moduledoc false

  @default_attempts 10
  @default_prefix "jido_integration_tmp"

  @spec create!(String.t() | atom() | [String.t() | atom()], keyword()) :: String.t()
  def create!(prefix, opts \\ []) do
    base_dir =
      opts
      |> Keyword.get(:base_dir, System.tmp_dir!())
      |> Path.expand()

    File.mkdir_p!(base_dir)

    prefix =
      prefix
      |> normalize_prefix()
      |> case do
        "" -> @default_prefix
        value -> value
      end

    create_unique_dir!(base_dir, prefix, Keyword.get(opts, :attempts, @default_attempts))
  end

  @spec cleanup!(String.t()) :: :ok
  def cleanup!(path) do
    File.rm_rf!(path)
    :ok
  end

  defp create_unique_dir!(_base_dir, prefix, 0) do
    raise "failed to create temp directory for #{inspect(prefix)}"
  end

  defp create_unique_dir!(base_dir, prefix, attempts_left) do
    path = Path.join(base_dir, "#{prefix}_#{unique_suffix()}")

    case File.mkdir(path) do
      :ok ->
        path

      {:error, :eexist} ->
        create_unique_dir!(base_dir, prefix, attempts_left - 1)

      {:error, reason} ->
        raise File.Error, reason: reason, action: "create directory", path: path
    end
  end

  defp unique_suffix do
    random_suffix = Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)

    [
      System.os_time(:microsecond),
      System.pid(),
      node(),
      random_suffix
    ]
    |> Enum.map_join("_", &normalize_segment/1)
  end

  defp normalize_prefix(prefix) when is_list(prefix) do
    prefix
    |> Enum.map(&normalize_segment/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("_")
  end

  defp normalize_prefix(prefix), do: normalize_prefix([prefix])

  defp normalize_segment(value) do
    value
    |> to_string()
    |> safe_segment_chars()
    |> String.trim("_")
  end

  defp safe_segment_chars(value) do
    value
    |> :binary.bin_to_list()
    |> Enum.map(fn byte ->
      if byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in [?., ?_, ?-] do
        byte
      else
        ?_
      end
    end)
    |> List.to_string()
  end
end
