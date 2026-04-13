defmodule Jido.RuntimeControl.SchemaTest do
  use ExUnit.Case, async: true

  alias Jido.RuntimeControl.{Error, RunRequest}

  test "run_request schema constructors validate inputs" do
    assert is_struct(RunRequest.schema())
    assert {:ok, %RunRequest{prompt: "hello"}} = RunRequest.new(%{prompt: "hello"})
    assert %RunRequest{prompt: "hello"} = RunRequest.new!(%{prompt: "hello"})
    assert {:error, _} = RunRequest.new(%{})
    assert_raise ArgumentError, ~r/Invalid Jido.RuntimeControl.RunRequest/, fn -> RunRequest.new!(%{}) end
  end

  test "error helper constructors build typed exceptions" do
    assert %Error.InvalidInputError{field: :runtime_id} =
             Error.validation_error("bad runtime id", %{field: :runtime_id})

    assert %Error.ExecutionFailureError{details: %{runtime_id: :asm}} =
             Error.execution_error("boom", %{runtime_id: :asm})
  end
end
