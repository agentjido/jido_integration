defmodule Jido.Integration.V2.Connectors.CodexCli.ConformanceHarnessDriver do
  @moduledoc false

  @table __MODULE__

  alias Jido.Harness.{ExecutionResult, RunRequest, SessionHandle}
  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.RuntimeResult

  @spec reset!() :: :ok
  def reset! do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ok
  end

  @spec start_session(keyword()) :: {:ok, SessionHandle.t()}
  def start_session(opts) when is_list(opts) do
    ensure_table!()
    session_id = "asm-session-" <> Integer.to_string(System.unique_integer([:positive]))
    true = :ets.insert(@table, {session_id, 0})

    {:ok,
     SessionHandle.new!(%{
       session_id: session_id,
       runtime_id: :asm,
       provider: Keyword.get(opts, :provider),
       status: :ready,
       metadata: %{}
     })}
  end

  @spec run(SessionHandle.t(), RunRequest.t(), keyword()) :: {:ok, ExecutionResult.t()}
  def run(%SessionHandle{} = session, %RunRequest{} = request, opts) when is_list(opts) do
    turn = next_turn!(session.session_id)
    capability = Keyword.fetch!(opts, :capability)
    context = Keyword.fetch!(opts, :context)
    prompt = Map.fetch!(Keyword.fetch!(opts, :input), :prompt)
    workspace = request.cwd
    tool = opts |> Keyword.get(:allowed_tools, []) |> List.first()
    auth_binding = ArtifactBuilder.digest(context.credential_lease.payload.access_token)
    reply = "codex(#{context.credential_lease.subject}) turn #{turn}: #{String.downcase(prompt)}"

    artifact =
      ArtifactBuilder.build!(
        run_id: context.run_id,
        attempt_id: context.attempt_id,
        artifact_type: :event_log,
        key: "codex_cli/#{context.run_id}/#{context.attempt_id}/turn_#{turn}.term",
        content: %{
          prompt: prompt,
          reply: reply,
          turn: turn,
          workspace: workspace,
          tool: tool
        },
        metadata: %{
          connector: "codex_cli",
          capability_id: capability.id,
          session_id: session.session_id,
          auth_binding: auth_binding
        }
      )

    runtime_result =
      RuntimeResult.new!(%{
        output: %{
          reply: reply,
          turn: turn,
          workspace: workspace,
          auth_binding: auth_binding,
          approval_mode: context.policy_inputs.execution.sandbox.approvals
        },
        runtime_ref_id: session.session_id,
        events: [
          %{
            type: lifecycle_event_type(Keyword.get(opts, :lifecycle, :started)),
            payload: %{provider: session.provider},
            session_id: session.session_id,
            runtime_ref_id: session.session_id
          },
          %{
            type: "connector.codex_cli.turn.completed",
            stream: :assistant,
            payload: %{
              turn: turn,
              workspace: workspace,
              tool: tool,
              auth_binding: auth_binding
            },
            session_id: session.session_id,
            runtime_ref_id: session.session_id
          }
        ],
        artifacts: [artifact]
      })

    {:ok,
     ExecutionResult.new!(%{
       run_id: Keyword.get(opts, :run_id, context.run_id),
       session_id: session.session_id,
       runtime_id: :asm,
       provider: session.provider,
       status: :completed,
       text: reply,
       messages: [],
       cost: %{},
       stop_reason: "completed",
       metadata: %{
         jido_integration: %{
           runtime_result: runtime_result
         }
       }
     })}
  end

  @spec stop_session(SessionHandle.t()) :: :ok
  def stop_session(%SessionHandle{session_id: session_id}) do
    ensure_table!()
    :ets.delete(@table, session_id)
    :ok
  end

  defp lifecycle_event_type(:reused), do: "session.reused"
  defp lifecycle_event_type(_other), do: "session.started"

  defp next_turn!(session_id) do
    ensure_table!()
    :ets.update_counter(@table, session_id, {2, 1})
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      _table ->
        @table
    end
  rescue
    ArgumentError ->
      @table
  end
end
