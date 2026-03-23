defmodule Mix.Tasks.Jido.TaskHelpTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "jido.conformance help describes connector acceptance expectations" do
    Mix.Task.reenable("help")

    output =
      capture_io(fn ->
        Mix.Tasks.Help.run(["jido.conformance"])
      end)
      |> normalize_whitespace()
      |> String.downcase()

    assert output =~ "connector acceptance contract"
    assert output =~ "package-local fixtures stay package-local"
    assert output =~ "mix ci"
  end

  test "jido.integration.new help describes the authored-vs-generated scaffold boundary" do
    Mix.Task.reenable("help")

    output =
      capture_io(fn ->
        Mix.Tasks.Help.run(["jido.integration.new"])
      end)
      |> normalize_whitespace()

    assert output =~ "generated starting contract"
    assert output =~ "still must be authored by hand"
    assert output =~ "proof code belongs in the generated connector package"
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
