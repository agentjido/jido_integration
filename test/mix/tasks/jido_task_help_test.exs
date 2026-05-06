defmodule Mix.Tasks.Jido.TaskHelpTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Help

  test "jido.conformance help describes connector acceptance expectations" do
    Mix.Task.reenable("help")

    output =
      capture_io(fn ->
        Help.run(["jido.conformance"])
      end)
      |> normalize_whitespace()
      |> String.downcase()

    assert String.contains?(output, "connector acceptance contract")
    assert String.contains?(output, "package-local fixtures stay package-local")
    assert String.contains?(output, "mix ci")
  end

  test "jido.integration.new help describes the authored-vs-generated scaffold boundary" do
    Mix.Task.reenable("help")

    output =
      capture_io(fn ->
        Help.run(["jido.integration.new"])
      end)
      |> normalize_whitespace()

    assert String.contains?(output, "generated starting contract")
    assert String.contains?(output, "still must be authored by hand")
    assert String.contains?(output, "proof code belongs in the generated connector package")
  end

  test "jido_integration.release.publish help describes bundle-first publication" do
    Mix.Task.reenable("help")

    output =
      capture_io(fn ->
        Help.run(["jido_integration.release.publish"])
      end)
      |> normalize_whitespace()

    assert String.contains?(output, "prepared welded release bundle")
    assert String.contains?(output, "publishes from the prepared bundle snapshot")
    assert String.contains?(output, "mix release.prepare")
  end

  defp normalize_whitespace(text), do: text |> String.split() |> Enum.join(" ")
end
