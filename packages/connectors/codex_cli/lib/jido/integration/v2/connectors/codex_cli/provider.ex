defmodule Jido.Integration.V2.Connectors.CodexCli.Provider do
  @moduledoc false

  @behaviour Jido.Integration.V2.SessionKernel.Provider

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.RuntimeResult

  @impl true
  def reuse_key(%Capability{id: capability_id}, context) do
    {capability_id, context.credential_ref.id}
  end

  @impl true
  def open_session(_capability, context) do
    {:ok,
     %{
       session_id: Contracts.next_id("session"),
       subject: context.credential_lease.subject,
       workspace: context.policy_inputs.execution.sandbox.file_scope,
       auth_binding:
         ArtifactBuilder.digest(lease_value(context.credential_lease.payload, :access_token)),
       turns: 0
     }}
  end

  @impl true
  def execute(capability, session, input, context) do
    turn = session.turns + 1
    prompt = Map.fetch!(input, :prompt)
    tool = List.first(context.policy_inputs.execution.sandbox.allowed_tools)

    updated_session = %{session | turns: turn}
    reply = "codex(#{session.subject}) turn #{turn}: #{String.downcase(prompt)}"

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
          workspace: session.workspace,
          tool: tool
        },
        metadata: %{
          connector: "codex_cli",
          capability_id: capability.id,
          session_id: session.session_id,
          auth_binding: session.auth_binding
        }
      )

    {:ok,
     RuntimeResult.new!(%{
       output: %{
         reply: reply,
         turn: turn,
         workspace: session.workspace,
         auth_binding: session.auth_binding,
         approval_mode: context.policy_inputs.execution.sandbox.approvals
       },
       events: [
         %{
           type: "connector.codex_cli.turn.completed",
           stream: :assistant,
           payload: %{
             turn: turn,
             workspace: session.workspace,
             tool: tool,
             auth_binding: session.auth_binding
           }
         }
       ],
       artifacts: [artifact]
     }), updated_session}
  end

  defp lease_value(payload, key) do
    case Contracts.get(payload, key) do
      nil -> raise ArgumentError, "missing credential lease field #{inspect(key)}"
      value -> value
    end
  end
end
