defmodule Jido.Integration.V2.Apps.InferenceOpsDocsTest do
  use ExUnit.Case, async: true

  @app_root Path.expand("../../../../../", __DIR__)

  test "the package readme lists the attached-local proof example surface" do
    readme = File.read!(Path.join(@app_root, "README.md"))

    assert String.contains?(readme, "run_ollama_attach_proof/1")
    assert String.contains?(readme, "examples/ollama_attach_proof.exs")
  end

  test "the examples readme explains how to run the honest attach proof" do
    readme = File.read!(Path.join(@app_root, "examples/README.md"))

    assert String.contains?(readme, "mix run examples/ollama_attach_proof.exs")
    assert String.contains?(readme, "OLLAMA_ROOT_URL")
    assert String.contains?(readme, "OLLAMA_MODEL")
    assert String.contains?(readme, "already running Ollama daemon")
  end
end
