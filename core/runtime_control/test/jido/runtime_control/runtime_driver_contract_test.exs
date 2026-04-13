defmodule Jido.RuntimeControl.RuntimeDriverContractTest do
  use ExUnit.Case, async: false

  use Jido.RuntimeControl.RuntimeDriverContract,
    driver: Jido.RuntimeControl.Test.RuntimeDriverStub,
    start_session_opts: [provider: :stub_runtime],
    check_stream_run: true,
    check_run: true,
    run_request: %{prompt: "contract test", metadata: %{}},
    run_opts: [run_id: "runtime-contract-run-1"]
end
