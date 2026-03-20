defmodule Jido.Integration.V2.Connectors.CodexCli.GeneratedConsumerSurfaceTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Connectors.CodexCli
  alias Jido.Integration.V2.Connectors.CodexCli.Generated.Actions.CodexExecSession
  alias Jido.Integration.V2.Connectors.CodexCli.Generated.Plugin, as: GeneratedPlugin
  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.InvocationRequest

  test "projects the common session surface through the shared consumer spine" do
    manifest = CodexCli.manifest()
    [operation] = manifest.operations
    action_module = ConsumerProjection.action_module(CodexCli, operation.operation_id)

    assert action_module == CodexExecSession
    assert Code.ensure_loaded?(action_module)
    assert Code.ensure_loaded?(GeneratedPlugin)
    assert action_module.operation_id() == "codex.exec.session"
    assert action_module.name() == "codex_exec_session"
    assert action_module.description() == operation.description
    assert action_module.category() == manifest.catalog.category
    assert action_module.schema() == operation.input_schema
    assert GeneratedPlugin.name() == "codex_cli"
    assert GeneratedPlugin.state_key() == :codex_cli
    assert GeneratedPlugin.actions() == [CodexExecSession]

    sample_output = %{
      reply: "Ready",
      turn: 1,
      workspace: "/workspaces/codex_cli",
      auth_binding: "binding-1",
      approval_mode: :manual
    }

    assert {:ok, ^sample_output} = Zoi.parse(operation.output_schema, sample_output)
    assert {:ok, ^sample_output} = Zoi.parse(action_module.output_schema(), sample_output)

    assert %InvocationRequest{
             capability_id: "codex.exec.session",
             connection_id: "conn-codex",
             input: %{prompt: "Summarize the review packet"},
             trace_id: "trace-codex-generated"
           } =
             ConsumerProjection.invocation_request!(
               CodexExecSession.generated_action_projection(),
               %{prompt: "Summarize the review packet", connection_id: "conn-codex"},
               %{trace_id: "trace-codex-generated"}
             )
  end
end
