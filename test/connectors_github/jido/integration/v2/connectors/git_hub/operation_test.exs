defmodule Jido.Integration.V2.Connectors.GitHub.OperationTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures
  alias Jido.Integration.V2.DirectRuntime
  alias Jido.Integration.V2.Redaction

  for spec <- Fixtures.specs() do
    test "#{spec.capability_id} executes through the direct runtime with deterministic github_ex fixtures" do
      spec = unquote(Macro.escape(spec))
      capability = fetch_capability!(spec.capability_id)

      assert {:ok, first_result} =
               DirectRuntime.execute(
                 capability,
                 spec.input,
                 Fixtures.execution_context(spec.capability_id,
                   github_client: Fixtures.client_opts(self())
                 )
               )

      assert_receive {:transport_request, request, _context}
      Fixtures.assert_request(spec.capability_id, request)

      assert {:ok, second_result} =
               DirectRuntime.execute(
                 capability,
                 spec.input,
                 Fixtures.execution_context(spec.capability_id,
                   github_client: Fixtures.client_opts(self())
                 )
               )

      assert_receive {:transport_request, request, _context}
      Fixtures.assert_request(spec.capability_id, request)

      assert runtime_summary(first_result) == runtime_summary(second_result)

      assert first_result.output == spec.output

      assert Enum.map(first_result.events, & &1.type) == [
               "attempt.started",
               spec.event_type,
               "attempt.completed"
             ]

      assert [artifact] = first_result.artifacts
      assert artifact.artifact_type == :tool_output
      assert artifact.payload_ref.store == "connector_review"
      assert artifact.payload_ref.key == spec.artifact_key
      assert artifact.metadata.connector == "github"
      assert artifact.metadata.capability_id == spec.capability_id
      assert artifact.metadata.auth_binding == Fixtures.auth_binding()

      refute inspect(%{
               output: first_result.output,
               events: first_result.events,
               artifact: artifact
             }) =~ Fixtures.access_token()
    end
  end

  test "normalizes github_ex errors into the Jido taxonomy and redacts auth material" do
    capability = fetch_capability!("github.issue.fetch")
    input = Fixtures.input_for("github.issue.fetch")

    assert {:error, mapped_error, result} =
             DirectRuntime.execute(
               capability,
               input,
               Fixtures.execution_context("github.issue.fetch",
                 github_client: [
                   transport: Fixtures.client_opts(self())[:transport],
                   transport_opts: [
                     test_pid: self(),
                     response: Fixtures.not_found_response()
                   ]
                 ]
               )
             )

    assert_receive {:transport_request, request, _context}
    Fixtures.assert_request("github.issue.fetch", request)

    assert mapped_error.code == "github.not_found"
    assert mapped_error.class == "invalid_request"
    assert mapped_error.retryability == :terminal
    assert mapped_error.message == "[not_found] Not Found (request_id: req-github-missing)"
    assert mapped_error.upstream_context.http_status == 404
    assert mapped_error.upstream_context.provider_request_id == "req-github-missing"
    assert mapped_error.upstream_context.provider_code == "not_found"
    assert mapped_error.upstream_context.retry_after_ms == nil
    assert mapped_error.upstream_context.body["token"] == Redaction.redacted()
    assert mapped_error.upstream_context.headers["authorization"] == Redaction.redacted()

    assert mapped_error.upstream_context.additional_data["errors"] == [
             %{"access_token" => Redaction.redacted()}
           ]

    assert result.output == %{
             capability_id: capability.id,
             auth_binding: Fixtures.auth_binding(),
             error: mapped_error
           }

    assert Enum.map(result.events, & &1.type) == [
             "attempt.started",
             "connector.github.issue.fetch.failed",
             "attempt.failed"
           ]

    assert [artifact] = result.artifacts

    assert artifact.payload_ref.key ==
             "github/run-github-test/run-github-test:1/issue_fetch_error.term"

    refute inspect(%{error: mapped_error, result: result, artifact: artifact}) =~
             Fixtures.access_token()
  end

  test "rejects malformed repo shapes and non-positive numeric inputs before calling github_ex" do
    issue_fetch = fetch_capability!("github.issue.fetch")

    assert {:error, mapped_error, _result} =
             DirectRuntime.execute(
               issue_fetch,
               %{repo: "agentjido/jido_integration_v2/extra", issue_number: 42},
               Fixtures.execution_context("github.issue.fetch",
                 github_client: Fixtures.client_opts(self())
               )
             )

    assert mapped_error.code == "github.invalid_repo"
    assert mapped_error.class == "invalid_request"

    refute_receive {:transport_request, _request, _context}

    assert {:error, mapped_error, _result} =
             DirectRuntime.execute(
               issue_fetch,
               %{repo: "agentjido/jido_integration_v2", issue_number: 0},
               Fixtures.execution_context("github.issue.fetch",
                 github_client: Fixtures.client_opts(self())
               )
             )

    assert mapped_error.code == "github.invalid_input"
    assert mapped_error.class == "invalid_request"
    assert mapped_error.upstream_context.field == :issue_number
    assert mapped_error.upstream_context.value == 0

    refute_receive {:transport_request, _request, _context}

    issue_list = fetch_capability!("github.issue.list")

    assert {:error, mapped_error, _result} =
             DirectRuntime.execute(
               issue_list,
               %{repo: "agentjido/jido_integration_v2", page: 0, per_page: 2},
               Fixtures.execution_context("github.issue.list",
                 github_client: Fixtures.client_opts(self())
               )
             )

    assert mapped_error.code == "github.invalid_input"
    assert mapped_error.upstream_context.field == :page
    assert mapped_error.upstream_context.value == 0

    refute_receive {:transport_request, _request, _context}
  end

  defp fetch_capability!(capability_id) do
    Enum.find(GitHub.manifest().capabilities, &(&1.id == capability_id)) ||
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
