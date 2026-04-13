defmodule Jido.Session.RuntimeControlDriverContractTest do
  use ExUnit.Case, async: false

  use Jido.RuntimeControl.RuntimeDriverContract,
    driver: Jido.Session.RuntimeControlDriver,
    start_session_opts: [provider: :jido_session, session_id: "contract-session-1"],
    check_stream_run: true,
    check_run: true,
    run_request: %{prompt: "contract test", metadata: %{"suite" => "contract"}},
    run_opts: [run_id: "contract-run-1"]
end
