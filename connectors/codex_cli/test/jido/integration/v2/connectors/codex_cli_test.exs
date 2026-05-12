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
             "codex.session.cancel",
             "codex.session.start",
             "codex.session.status",
             "codex.session.stream",
             "codex.session.turn"
           ]

    refute Map.has_key?(capabilities_by_id, "codex.session.approve")
    refute Map.has_key?(capabilities_by_id, "codex.session.tool.respond")

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
    assert capability.metadata.policy.sandbox.file_scope == "/tmp/jido_codex_cli_workspace"
    assert capability.metadata.policy.sandbox.allowed_tools == ["codex.session.turn"]
    assert capability.metadata.session_control.operation == :turn
    assert capability.metadata.codex_app_server.primary? == true
    assert capability.metadata.codex_app_server.host_tools == :native
    assert capability.metadata.lower_runtime_kinds == [:codex_session, :deterministic_fixture]
    assert capability.metadata.side_effect_class == :execute
    assert capability.metadata.idempotency_class == :non_idempotent

    assert capabilities_by_id["codex.session.start"].metadata.session_control.operation == :start

    assert capabilities_by_id["codex.session.status"].metadata.session_control.operation ==
             :status

    assert capabilities_by_id["codex.session.cancel"].metadata.session_control.operation ==
             :cancel

    assert capabilities_by_id["codex.session.stream"].metadata.session_control.operation ==
             :stream
  end

  test "control operation schemas require concrete control identifiers" do
    manifest = CodexCli.manifest()
    operations_by_id = Map.new(manifest.operations, &{&1.operation_id, &1})

    status = Map.fetch!(operations_by_id, "codex.session.status")
    cancel = Map.fetch!(operations_by_id, "codex.session.cancel")

    assert {:error, _} = Zoi.parse(status.input_schema, %{})

    assert {:ok, %{session_id: "session-1"}} =
             Zoi.parse(status.input_schema, %{session_id: "session-1"})

    assert {:error, _} = Zoi.parse(cancel.input_schema, %{session_id: "session-1"})

    assert {:ok, %{session_id: "session-1", run_id: "run-1"}} =
             Zoi.parse(cancel.input_schema, %{session_id: "session-1", run_id: "run-1"})
  end

  test "turn schema accepts governed headless Codex runtime input" do
    operation =
      CodexCli.manifest().operations
      |> Enum.find(&(&1.operation_id == "codex.session.turn"))

    assert {:ok, validated} =
             Zoi.parse(operation.input_schema, %{
               prompt: "Implement the governed slice",
               cwd: "/workspace/extravaganza",
               workspace: %{"workspace_ref" => "workspace://phase5"},
               host_tools: [
                 %{
                   name: "linear_comment_update",
                   inputSchema: %{"type" => "object"},
                   metadata: %{"operation_id" => "linear.comments.update"}
                 }
               ],
               continuation: %{strategy: :latest},
               provider_metadata: %{"model" => "gpt-5.4"},
               authority_metadata: %{
                 "authority_ref" => "authority://phase5",
                 "allowed_operations" => ["codex.session.turn"]
               },
               dynamic_tool_manifest: %{"tools" => ["linear.comment.update"]},
               governed_lower_envelope: %{
                 "lower_runtime_kind" => "codex_session",
                 "authority_decision_hash" => "hash-123"
               }
             })

    assert validated.cwd == "/workspace/extravaganza"
    assert validated.dynamic_tool_manifest == %{"tools" => ["linear.comment.update"]}
    assert validated.authority_metadata["authority_ref"] == "authority://phase5"
    assert validated.governed_lower_envelope["lower_runtime_kind"] == "codex_session"
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
