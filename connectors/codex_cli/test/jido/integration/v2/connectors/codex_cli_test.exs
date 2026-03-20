defmodule Jido.Integration.V2.Connectors.CodexCliTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Connectors.CodexCli
  alias Jido.Integration.V2.Connectors.CodexCli.Conformance

  test "publishes a session capability manifest" do
    manifest = CodexCli.manifest()
    [capability] = manifest.capabilities

    assert manifest.connector == "codex_cli"
    assert capability.id == "codex.exec.session"
    assert capability.runtime_class == :session

    assert capability.metadata.runtime == %{
             driver: "asm",
             provider: :codex,
             options: %{}
           }

    assert capability.metadata.consumer_surface == %{
             mode: :common,
             normalized_id: "codex.exec.session",
             action_name: "codex_exec_session"
           }

    assert capability.metadata.runtime_family == %{
             session_affinity: :connection,
             resumable: true,
             approval_required: true,
             stream_capable: true,
             lifecycle_owner: :asm,
             runtime_ref: :session
           }

    assert capability.metadata.required_scopes == ["session:execute"]
    assert capability.metadata.policy.environment.allowed == [:prod]
    assert capability.metadata.policy.sandbox.file_scope == "/workspaces/codex_cli"
    assert capability.metadata.policy.sandbox.allowed_tools == ["codex.exec.session"]
  end

  test "publishes deterministic conformance fixtures" do
    assert [%{capability_id: "codex.exec.session"}] = Conformance.fixtures()
  end
end
