defmodule Jido.Integration.V2.Connectors.CodexCli.GeneratedConsumerSurfaceTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Connectors.CodexCli
  alias Jido.Integration.V2.Connectors.CodexCli.Generated.Actions.CodexSessionCancel
  alias Jido.Integration.V2.Connectors.CodexCli.Generated.Actions.CodexSessionStart
  alias Jido.Integration.V2.Connectors.CodexCli.Generated.Actions.CodexSessionStatus
  alias Jido.Integration.V2.Connectors.CodexCli.Generated.Actions.CodexSessionStream
  alias Jido.Integration.V2.Connectors.CodexCli.Generated.Actions.CodexSessionTurn
  alias Jido.Integration.V2.Connectors.CodexCli.Generated.Plugin, as: GeneratedPlugin
  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.InvocationRequest

  test "projects the common session surface through the shared consumer spine" do
    manifest = CodexCli.manifest()
    operation = Enum.find(manifest.operations, &(&1.operation_id == "codex.session.turn"))
    action_module = ConsumerProjection.action_module(CodexCli, operation.operation_id)

    assert action_module == CodexSessionTurn
    assert Code.ensure_loaded?(action_module)
    assert Code.ensure_loaded?(GeneratedPlugin)
    assert action_module.operation_id() == "codex.session.turn"
    assert action_module.name() == "codex_session_turn"
    assert action_module.description() == operation.description
    assert action_module.category() == manifest.catalog.category
    assert GeneratedPlugin.name() == "codex_cli"
    assert GeneratedPlugin.state_key() == :codex_cli

    assert GeneratedPlugin.actions() == [
             CodexSessionCancel,
             CodexSessionStart,
             CodexSessionStatus,
             CodexSessionStream,
             CodexSessionTurn
           ]

    assert Code.ensure_loaded?(CodexSessionCancel)
    assert Code.ensure_loaded?(CodexSessionStart)
    assert Code.ensure_loaded?(CodexSessionStatus)
    assert Code.ensure_loaded?(CodexSessionStream)
    assert CodexSessionTurn in GeneratedPlugin.actions()
    refute Enum.any?(GeneratedPlugin.actions(), &(to_string(&1) =~ "ToolRespond"))
    refute Enum.any?(GeneratedPlugin.actions(), &(to_string(&1) =~ "Approve"))

    sample_input = %{
      prompt: "Summarize the review packet",
      host_tools: [
        %{
          name: "echo_json",
          description: "Echo a JSON payload",
          inputSchema: %{type: "object"},
          outputSchema: %{type: "object"}
        }
      ],
      continuation: %{provider_session_id: "codex-thread-1"},
      provider_metadata: %{cwd: "/workspace"}
    }

    assert {:ok, validated_input} = Zoi.parse(operation.input_schema, sample_input)
    assert {:ok, ^validated_input} = Zoi.parse(action_module.schema(), sample_input)

    sample_output = %{
      text: "Ready",
      provider_session_id: "codex-thread-1",
      status: :completed,
      auth_binding: "binding-1",
      events: []
    }

    assert {:ok, ^sample_output} = Zoi.parse(operation.output_schema, sample_output)
    assert {:ok, ^sample_output} = Zoi.parse(action_module.output_schema(), sample_output)

    assert %InvocationRequest{
             capability_id: "codex.session.turn",
             connection_id: "conn-codex",
             input: %{prompt: "Summarize the review packet"},
             trace_id: "trace-codex-generated"
           } =
             ConsumerProjection.invocation_request!(
               CodexSessionTurn.generated_action_projection(),
               %{prompt: "Summarize the review packet", connection_id: "conn-codex"},
               %{trace_id: "trace-codex-generated"}
             )

    assert %InvocationRequest{
             capability_id: "codex.session.status",
             connection_id: "conn-codex",
             input: %{session_id: "runtime-session-1"}
           } =
             ConsumerProjection.invocation_request!(
               CodexSessionStatus.generated_action_projection(),
               %{session_id: "runtime-session-1", connection_id: "conn-codex"},
               %{}
             )
  end
end
