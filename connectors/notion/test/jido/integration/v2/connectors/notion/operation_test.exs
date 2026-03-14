defmodule Jido.Integration.V2.Connectors.Notion.OperationTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.Notion
  alias Jido.Integration.V2.Connectors.Notion.Fixtures
  alias Jido.Integration.V2.Connectors.Notion.FixtureTransport
  alias Jido.Integration.V2.DirectRuntime
  alias Jido.Integration.V2.Redaction

  test "executes a published capability through the direct runtime with deterministic transport fixtures" do
    capability = fetch_capability!("notion.pages.retrieve")
    input = Fixtures.input_for("notion.pages.retrieve")

    assert {:ok, first_result} =
             DirectRuntime.execute(capability, input, execution_context("notion.pages.retrieve"))

    assert_receive {:transport_request, request, _context}
    assert request.method == :get
    assert request.url == Fixtures.request_url("notion.pages.retrieve")
    assert request.headers["Authorization"] == "Bearer #{Fixtures.access_token()}"

    assert {:ok, second_result} =
             DirectRuntime.execute(capability, input, execution_context("notion.pages.retrieve"))

    assert_receive {:transport_request, _request, _context}

    assert runtime_summary(first_result) == runtime_summary(second_result)

    assert first_result.output == %{
             capability_id: capability.id,
             auth_binding: Fixtures.auth_binding(),
             data: Fixtures.output_data("notion.pages.retrieve")
           }

    assert Enum.map(first_result.events, & &1.type) == [
             "attempt.started",
             "connector.notion.pages.retrieve.completed",
             "attempt.completed"
           ]

    assert [artifact] = first_result.artifacts
    assert artifact.artifact_type == :tool_output
    assert artifact.payload_ref.store == "connector_review"

    assert artifact.payload_ref.key ==
             "notion/run-notion-test/run-notion-test:1/pages_retrieve.term"

    assert artifact.metadata.connector == "notion"
    assert artifact.metadata.capability_id == "notion.pages.retrieve"
    assert artifact.metadata.auth_binding == Fixtures.auth_binding()

    refute inspect(%{
             output: first_result.output,
             events: first_result.events,
             artifact: artifact
           }) =~ Fixtures.access_token()
  end

  test "normalizes Notion provider errors into the Jido taxonomy and redacts auth material" do
    capability = fetch_capability!("notion.pages.retrieve")
    input = Fixtures.input_for("notion.pages.retrieve")

    assert {:error, mapped_error, result} =
             DirectRuntime.execute(
               capability,
               input,
               execution_context("notion.pages.retrieve", response: Fixtures.not_found_error())
             )

    assert mapped_error.code == "notion.object_not_found"
    assert mapped_error.class == "invalid_request"
    assert mapped_error.retryability == :terminal

    assert mapped_error.message ==
             "Notion could not find the target, or the integration is not shared to it"

    assert mapped_error.upstream_context.http_status == 404
    assert mapped_error.upstream_context.provider_request_id == "req-notion-missing"
    assert mapped_error.upstream_context.provider_code == "object_not_found"
    assert mapped_error.upstream_context.retry_after_ms == nil
    assert mapped_error.upstream_context.body["access_token"] == Redaction.redacted()
    assert mapped_error.upstream_context.headers["authorization"] == Redaction.redacted()
    assert mapped_error.upstream_context.additional_data["refresh_token"] == Redaction.redacted()

    assert result.output == %{
             capability_id: capability.id,
             auth_binding: Fixtures.auth_binding(),
             error: mapped_error
           }

    assert Enum.map(result.events, & &1.type) == [
             "attempt.started",
             "connector.notion.pages.retrieve.failed",
             "attempt.failed"
           ]

    assert [artifact] = result.artifacts

    assert artifact.payload_ref.key ==
             "notion/run-notion-test/run-notion-test:1/pages_retrieve_error.term"

    refute inspect(%{error: mapped_error, result: result, artifact: artifact}) =~
             Fixtures.access_token()
  end

  defp execution_context(capability_id, opts \\ []) do
    Fixtures.execution_context(capability_id,
      notion_client: [
        transport: FixtureTransport,
        transport_opts: [test_pid: self(), response: Keyword.get(opts, :response)]
      ]
    )
  end

  defp fetch_capability!(capability_id) do
    Enum.find(Notion.manifest().capabilities, &(&1.id == capability_id)) ||
      raise "missing capability #{capability_id}"
  end

  defp runtime_summary(result) do
    %{
      output: result.output,
      events: result.events,
      artifacts:
        Enum.map(result.artifacts, fn artifact ->
          %{
            artifact_type: artifact.artifact_type,
            key: artifact.payload_ref.key,
            checksum: artifact.checksum,
            size_bytes: artifact.size_bytes,
            metadata: artifact.metadata
          }
        end)
    }
  end
end
