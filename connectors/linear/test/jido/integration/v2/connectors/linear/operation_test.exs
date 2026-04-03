defmodule Jido.Integration.V2.Connectors.Linear.OperationTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.Linear
  alias Jido.Integration.V2.Connectors.Linear.ClientFactory
  alias Jido.Integration.V2.Connectors.Linear.Fixtures
  alias Jido.Integration.V2.Connectors.Linear.InstallBinding
  alias Jido.Integration.V2.DirectRuntime
  alias Jido.Integration.V2.Redaction

  for spec <- Fixtures.specs() do
    test "#{spec.capability_id} executes through the direct runtime with deterministic linear_sdk fixtures" do
      spec = unquote(Macro.escape(spec))
      capability = fetch_capability!(spec.capability_id)

      assert {:ok, first_result} =
               DirectRuntime.execute(
                 capability,
                 spec.input,
                 Fixtures.execution_context(spec.capability_id,
                   linear_request: Fixtures.request_opts(self())
                 )
               )

      assert_receive {:transport_request, payload, context, _opts}
      Fixtures.assert_request(spec.capability_id, payload, context)

      assert {:ok, second_result} =
               DirectRuntime.execute(
                 capability,
                 spec.input,
                 Fixtures.execution_context(spec.capability_id,
                   linear_request: Fixtures.request_opts(self())
                 )
               )

      assert_receive {:transport_request, payload, context, _opts}
      Fixtures.assert_request(spec.capability_id, payload, context)

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
      assert artifact.metadata.connector == "linear"
      assert artifact.metadata.capability_id == spec.capability_id
      assert artifact.metadata.auth_binding == Fixtures.auth_binding()

      refute inspect(%{
               output: first_result.output,
               events: first_result.events,
               artifact: artifact
             }) =~ Fixtures.api_key()
    end
  end

  test "normalizes LinearSDK errors into the Jido taxonomy and redacts auth material" do
    capability = fetch_capability!("linear.issues.retrieve")
    input = Fixtures.input_for("linear.issues.retrieve")

    assert {:error, mapped_error, result} =
             DirectRuntime.execute(
               capability,
               input,
               Fixtures.execution_context("linear.issues.retrieve",
                 linear_request:
                   Fixtures.request_opts(self(),
                     response: Fixtures.not_found_response()
                   )
               )
             )

    assert_receive {:transport_request, payload, context, _opts}
    Fixtures.assert_request("linear.issues.retrieve", payload, context)

    assert mapped_error.code == "linear.not_found"
    assert mapped_error.class == "invalid_request"
    assert mapped_error.retryability == :terminal
    assert mapped_error.message == "[not_found] Issue not found (request_id: req-linear-missing)"
    assert mapped_error.upstream_context.http_status == 200
    assert mapped_error.upstream_context.provider_request_id == "req-linear-missing"
    assert mapped_error.upstream_context.provider_code == "NOT_FOUND"

    assert mapped_error.upstream_context.body["body"] == %{
             "api_key" => Redaction.redacted()
           }

    assert mapped_error.upstream_context.graphql_errors == [
             %{
               "message" => "Issue not found",
               "extensions" => %{"code" => "NOT_FOUND"},
               "body" => %{"api_key" => Redaction.redacted()}
             }
           ]

    assert result.output == %{
             capability_id: capability.id,
             auth_binding: Fixtures.auth_binding(),
             error: mapped_error
           }

    assert Enum.map(result.events, & &1.type) == [
             "attempt.started",
             "connector.linear.issues.retrieve.failed",
             "attempt.failed"
           ]

    assert [artifact] = result.artifacts

    assert artifact.payload_ref.key ==
             "linear/run-linear-test/run-linear-test:1/issues_retrieve_error.term"

    refute inspect(%{error: mapped_error, result: result, artifact: artifact}) =~
             Fixtures.api_key()
  end

  test "rejects empty Linear issue updates before calling linear_sdk" do
    capability = fetch_capability!("linear.issues.update")

    assert {:error, mapped_error, _result} =
             DirectRuntime.execute(
               capability,
               %{issue_id: "lin-issue-321"},
               Fixtures.execution_context("linear.issues.update",
                 linear_request: Fixtures.request_opts(self())
               )
             )

    assert mapped_error.code == "linear.preflight_validation"
    assert mapped_error.class == "invalid_request"

    refute_receive {:transport_request, _payload, _context, _opts}
  end

  test "runtime execution and client construction do not invoke InstallBinding" do
    capability = fetch_capability!("linear.users.get_self")
    trace_pattern = {InstallBinding, :_, :_}

    :erlang.trace(self(), true, [:call])
    :erlang.trace_pattern(trace_pattern, true, [:local])

    on_exit(fn ->
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern(trace_pattern, false, [:local])
    end)

    assert {:ok, _client} =
             ClientFactory.build(%{
               credential_lease: Fixtures.credential_lease(),
               opts: Fixtures.execution_context("linear.users.get_self").opts
             })

    assert {:ok, _result} =
             DirectRuntime.execute(
               capability,
               %{},
               Fixtures.execution_context("linear.users.get_self",
                 linear_request: Fixtures.request_opts(self())
               )
             )

    refute_receive {:trace, _pid, :call, {InstallBinding, _function, _args}}
  end

  defp fetch_capability!(capability_id) do
    Enum.find(Linear.manifest().capabilities, &(&1.id == capability_id)) ||
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
