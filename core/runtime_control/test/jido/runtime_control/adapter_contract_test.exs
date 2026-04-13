defmodule Jido.RuntimeControl.AdapterContractTest do
  use ExUnit.Case, async: false

  use Jido.RuntimeControl.AdapterContract,
    adapter: Jido.RuntimeControl.Test.AdapterStub,
    provider: :stub,
    check_run: true,
    run_request: %{prompt: "contract test", metadata: %{}}
end
