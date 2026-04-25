defmodule Jido.Integration.V2.Connectors.CodexCliTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Connectors.CodexCli
  alias Jido.Integration.V2.Connectors.CodexCli.Conformance

  test "publishes a session capability manifest" do
    manifest = CodexCli.manifest()
    capabilities_by_id = Map.new(manifest.capabilities, &{&1.id, &1})
    capability = Map.fetch!(capabilities_by_id, "codex.session.turn")

    assert manifest.connector == "codex_cli"

    assert Map.keys(capabilities_by_id) == [
             "codex.session.approve",
             "codex.session.cancel",
             "codex.session.start",
             "codex.session.status",
             "codex.session.stream",
             "codex.session.tool.respond",
             "codex.session.turn"
           ]

    assert capability.runtime_class == :session

    assert capability.metadata.runtime == %{
             driver: "asm",
             provider: :codex,
             options: %{app_server: true}
           }

    assert capability.metadata.consumer_surface == %{
             mode: :common,
             normalized_id: "codex.session.turn",
             action_name: "codex_session_turn"
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
    assert capability.metadata.policy.sandbox.allowed_tools == ["codex.session.turn"]
    assert capability.metadata.codex_app_server.primary? == true
    assert capability.metadata.codex_app_server.host_tools == :native
  end

  test "publishes deterministic conformance fixtures" do
    assert [
             %{
               capability_id: "codex.session.turn",
               expect: %{
                 event_types: [
                   "session.started",
                   "connector.codex_cli.turn.completed"
                 ]
               }
             }
           ] = Conformance.fixtures()
  end
end
