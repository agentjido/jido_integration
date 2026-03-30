defmodule Jido.Integration.Toolchain do
  @moduledoc false

  @spec mix_executable() :: String.t()
  def mix_executable do
    mix_beam_path()
    |> mix_installation_executable()
    |> case do
      nil -> System.find_executable("mix") || "mix"
      path -> path
    end
  end

  defp mix_beam_path do
    case :code.which(Mix) do
      beam_path when is_list(beam_path) -> List.to_string(beam_path)
      _other -> nil
    end
  end

  defp mix_installation_executable(nil), do: nil

  defp mix_installation_executable(beam_path) do
    candidate =
      beam_path
      |> Path.expand()
      |> Path.dirname()
      |> Path.dirname()
      |> Path.dirname()
      |> Path.dirname()
      |> Path.join("bin/mix")

    if File.regular?(candidate), do: candidate
  end
end
