defmodule Jido.Integration.V2.Connectors.CodexCli.Conformance do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Connectors.CodexCli.ConformanceRuntimeControlDriver

  @run_id "run-codex-cli-conformance"
  @attempt_id "#{@run_id}:1"
  @subject "operator"
  @access_token "codex-demo-token"
  @prompt "Summarize Open Risk"

  @spec fixtures() :: [map()]
  def fixtures do
    [
      %{
        capability_id: "codex.exec.session",
        input: %{prompt: @prompt},
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{
          run_id: @run_id,
          attempt_id: @attempt_id
        },
        expect: %{
          output: %{
            reply: "codex(#{@subject}) turn 1: #{String.downcase(@prompt)}",
            turn: 1,
            workspace: "/workspaces/codex_cli",
            auth_binding: ArtifactBuilder.digest(@access_token),
            approval_mode: :manual
          },
          event_types: [
            "session.started",
            "connector.codex_cli.turn.completed"
          ],
          artifact_types: [:event_log],
          artifact_keys: ["codex_cli/#{@run_id}/#{@attempt_id}/turn_1.term"]
        }
      }
    ]
  end

  @spec runtime_drivers() :: map()
  def runtime_drivers do
    %{asm: ConformanceRuntimeControlDriver}
  end

  defp credential_ref do
    %{
      id: "cred-codex-cli-conformance",
      subject: @subject,
      scopes: ["session:execute"]
    }
  end

  defp credential_lease do
    %{
      lease_id: "lease-codex-cli-conformance",
      credential_ref_id: "cred-codex-cli-conformance",
      subject: @subject,
      scopes: ["session:execute"],
      payload: %{access_token: @access_token},
      issued_at: ~U[2026-03-12 00:00:00Z],
      expires_at: ~U[2026-03-12 00:05:00Z]
    }
  end
end
