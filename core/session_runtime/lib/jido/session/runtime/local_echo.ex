defmodule Jido.Session.Runtime.LocalEcho do
  @moduledoc """
  First internal session type for `jido_session`.

  The runtime stays intentionally narrow for Phase 2: it accepts a prompt and
  deterministically projects one assistant response without depending on an
  external provider loop.
  """

  alias Jido.Harness.RunRequest
  alias Jido.Session.Runtime.{Run, Session}

  @spec start_run(Session.t(), RunRequest.t(), keyword()) :: {:ok, Run.t()}
  def start_run(
        %Session{session_type: :local_echo} = session,
        %RunRequest{} = request,
        opts \\ []
      ) do
    {:ok, Run.start(session, request, opts)}
  end

  @spec complete_run(Session.t(), Run.t(), RunRequest.t(), keyword()) :: {:ok, Run.t()}
  def complete_run(
        %Session{session_type: :local_echo} = session,
        %Run{} = run,
        %RunRequest{} = request,
        _opts \\ []
      ) do
    text = "handled: #{String.trim(request.prompt)}"

    {:ok,
     Run.complete(run, %{
       result_text: text,
       messages: run.messages ++ [%{"role" => "assistant", "content" => text}],
       completed_at: run.started_at,
       duration_ms: 0,
       stop_reason: "completed",
       metadata: %{
         "request_metadata" => request.metadata,
         "session_metadata" => session.metadata,
         "session_type" => Atom.to_string(session.session_type)
       }
     })}
  end
end
