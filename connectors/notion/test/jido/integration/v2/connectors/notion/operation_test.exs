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

    assert_receive {:transport_request, page_request, _context}
    assert page_request.method == :get
    assert page_request.url == Fixtures.request_url("notion.pages.retrieve")
    assert page_request.headers["Authorization"] == "Bearer #{Fixtures.access_token()}"

    assert_receive {:transport_request, schema_request, _context}
    assert schema_request.method == :get
    assert schema_request.url == Fixtures.request_url("notion.data_sources.retrieve")
    assert schema_request.headers["Authorization"] == "Bearer #{Fixtures.access_token()}"

    assert {:ok, second_result} =
             DirectRuntime.execute(capability, input, execution_context("notion.pages.retrieve"))

    assert_receive {:transport_request, second_page_request, _context}
    assert second_page_request.method == :get
    assert second_page_request.url == Fixtures.request_url("notion.pages.retrieve")

    assert_receive {:transport_request, second_schema_request, _context}
    assert second_schema_request.method == :get
    assert second_schema_request.url == Fixtures.request_url("notion.data_sources.retrieve")

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

  test "resolves parent data-source schema before notion.pages.create and records schema context" do
    capability = fetch_capability!("notion.pages.create")
    input = Fixtures.input_for("notion.pages.create")

    assert {:ok, result} =
             DirectRuntime.execute(capability, input, execution_context("notion.pages.create"))

    assert_receive {:transport_request, schema_request, _context}
    assert schema_request.method == :get
    assert schema_request.url == Fixtures.request_url("notion.data_sources.retrieve")

    assert_receive {:transport_request, create_request, _context}
    assert create_request.method == :post
    assert create_request.url == Fixtures.request_url("notion.pages.create")

    assert result.output == %{
             capability_id: capability.id,
             auth_binding: Fixtures.auth_binding(),
             data: Fixtures.output_data("notion.pages.create")
           }

    connector_event = Enum.at(result.events, 1)

    assert connector_event.payload.schema_context == %{
             context_source: :parent_data_source,
             data_source_id: Fixtures.data_source_id(),
             property_names: ["Status", "Title"],
             resolved_via: [:data_source],
             slot_kinds: [:data_source_properties]
           }

    assert [artifact] = result.artifacts
    assert artifact.metadata.schema_context == connector_event.payload.schema_context
  end

  test "rejects notion.pages.create before provider invocation when properties do not match the parent data-source schema" do
    capability = fetch_capability!("notion.pages.create")
    create_url = Fixtures.request_url("notion.pages.create")

    input =
      Fixtures.input_for("notion.pages.create")
      |> put_in([:properties, "Bogus"], %{"rich_text" => [%{"plain_text" => "nope"}]})

    assert {:error, mapped_error, result} =
             DirectRuntime.execute(capability, input, execution_context("notion.pages.create"))

    assert_receive {:transport_request, schema_request, _context}
    assert schema_request.method == :get
    assert schema_request.url == Fixtures.request_url("notion.data_sources.retrieve")
    refute_receive {:transport_request, %{url: ^create_url}, _context}

    assert mapped_error.code == "notion.preflight_validation"
    assert mapped_error.class == "invalid_request"
    assert mapped_error.retryability == :terminal
    assert mapped_error.upstream_context.phase == :preflight

    assert mapped_error.upstream_context.issues == [
             %{
               kind: :data_source_properties,
               path: ["properties", "Bogus"],
               property: "Bogus",
               source: :parent_data_source
             }
           ]

    assert mapped_error.upstream_context.schema_context == %{
             context_source: :parent_data_source,
             data_source_id: Fixtures.data_source_id(),
             property_names: ["Status", "Title"],
             resolved_via: [:data_source],
             slot_kinds: [:data_source_properties]
           }

    assert Enum.map(result.events, & &1.type) == [
             "attempt.started",
             "connector.notion.pages.create.failed",
             "attempt.failed"
           ]
  end

  test "resolves page-parent schema before notion.pages.update and carries the schema context through the result" do
    capability = fetch_capability!("notion.pages.update")
    input = Fixtures.input_for("notion.pages.update")

    assert {:ok, result} =
             DirectRuntime.execute(capability, input, execution_context("notion.pages.update"))

    assert_receive {:transport_request, page_request, _context}
    assert page_request.method == :get
    assert page_request.url == Fixtures.request_url("notion.pages.retrieve")

    assert_receive {:transport_request, schema_request, _context}
    assert schema_request.method == :get
    assert schema_request.url == Fixtures.request_url("notion.data_sources.retrieve")

    assert_receive {:transport_request, update_request, _context}
    assert update_request.method == :patch
    assert update_request.url == Fixtures.request_url("notion.pages.update")

    connector_event = Enum.at(result.events, 1)

    assert connector_event.payload.schema_context == %{
             context_source: :page_parent_data_source,
             data_source_id: Fixtures.data_source_id(),
             property_names: ["Status", "Title"],
             resolved_via: [:page, :data_source],
             slot_kinds: [:data_source_properties],
             source_page_id: "00000000-0000-0000-0000-000000000010"
           }

    assert [artifact] = result.artifacts
    assert artifact.metadata.schema_context == connector_event.payload.schema_context
  end

  test "resolves a legacy database parent before notion.pages.update preflight validation" do
    capability = fetch_capability!("notion.pages.update")
    update_url = Fixtures.request_url("notion.pages.update")

    input =
      Fixtures.input_for("notion.pages.update")
      |> put_in([:properties, "Bogus"], %{"rich_text" => [%{"plain_text" => "nope"}]})

    assert {:error, mapped_error, result} =
             DirectRuntime.execute(
               capability,
               input,
               execution_context("notion.pages.update",
                 response: &legacy_database_parent_response/2
               )
             )

    assert_receive {:transport_request, page_request, _context}
    assert page_request.method == :get
    assert page_request.url == Fixtures.request_url("notion.pages.retrieve")

    assert_receive {:transport_request, database_request, _context}
    assert database_request.method == :get
    assert database_request.url == Fixtures.request_url("notion.databases.retrieve")

    assert_receive {:transport_request, schema_request, _context}
    assert schema_request.method == :get
    assert schema_request.url == Fixtures.request_url("notion.data_sources.retrieve")

    refute_receive {:transport_request, %{url: ^update_url}, _context}

    assert mapped_error.code == "notion.preflight_validation"
    assert mapped_error.class == "invalid_request"
    assert mapped_error.retryability == :terminal
    assert mapped_error.upstream_context.phase == :preflight

    assert mapped_error.upstream_context.issues == [
             %{
               kind: :data_source_properties,
               path: ["properties", "Bogus"],
               property: "Bogus",
               source: :page_parent_data_source
             }
           ]

    assert mapped_error.upstream_context.schema_context == %{
             context_source: :page_parent_data_source,
             data_source_id: Fixtures.data_source_id(),
             property_names: ["Status", "Title"],
             resolved_via: [:page, :database, :data_source],
             slot_kinds: [:data_source_properties],
             source_page_id: "00000000-0000-0000-0000-000000000010"
           }

    assert Enum.map(result.events, & &1.type) == [
             "attempt.started",
             "connector.notion.pages.update.failed",
             "attempt.failed"
           ]
  end

  test "annotates notion.pages.retrieve with resolved parent data-source schema context" do
    capability = fetch_capability!("notion.pages.retrieve")
    input = Fixtures.input_for("notion.pages.retrieve")

    assert {:ok, result} =
             DirectRuntime.execute(capability, input, execution_context("notion.pages.retrieve"))

    assert_receive {:transport_request, page_request, _context}
    assert page_request.method == :get
    assert page_request.url == Fixtures.request_url("notion.pages.retrieve")

    assert_receive {:transport_request, schema_request, _context}
    assert schema_request.method == :get
    assert schema_request.url == Fixtures.request_url("notion.data_sources.retrieve")

    connector_event = Enum.at(result.events, 1)

    assert connector_event.payload.schema_context == %{
             context_source: :page_parent_data_source,
             data_source_id: Fixtures.data_source_id(),
             property_names: ["Status", "Title"],
             resolved_via: [:page, :data_source],
             slot_kinds: [:data_source_properties],
             source_page_id: "00000000-0000-0000-0000-000000000010"
           }
  end

  test "annotates notion.pages.retrieve when the page resolves through a legacy database parent" do
    capability = fetch_capability!("notion.pages.retrieve")
    input = Fixtures.input_for("notion.pages.retrieve")

    assert {:ok, result} =
             DirectRuntime.execute(
               capability,
               input,
               execution_context("notion.pages.retrieve",
                 response: &legacy_database_parent_response/2
               )
             )

    assert_receive {:transport_request, page_request, _context}
    assert page_request.method == :get
    assert page_request.url == Fixtures.request_url("notion.pages.retrieve")

    assert_receive {:transport_request, database_request, _context}
    assert database_request.method == :get
    assert database_request.url == Fixtures.request_url("notion.databases.retrieve")

    assert_receive {:transport_request, schema_request, _context}
    assert schema_request.method == :get
    assert schema_request.url == Fixtures.request_url("notion.data_sources.retrieve")

    connector_event = Enum.at(result.events, 1)

    assert connector_event.payload.schema_context == %{
             context_source: :page_parent_data_source,
             data_source_id: Fixtures.data_source_id(),
             property_names: ["Status", "Title"],
             resolved_via: [:page, :database, :data_source],
             slot_kinds: [:data_source_properties],
             source_page_id: "00000000-0000-0000-0000-000000000010"
           }

    assert [artifact] = result.artifacts
    assert artifact.metadata.schema_context == connector_event.payload.schema_context
  end

  test "resolves schema before notion.data_sources.query and validates late-bound filter and sorts" do
    capability = fetch_capability!("notion.data_sources.query")
    input = Fixtures.input_for("notion.data_sources.query")

    assert {:ok, result} =
             DirectRuntime.execute(
               capability,
               input,
               execution_context("notion.data_sources.query")
             )

    assert_receive {:transport_request, schema_request, _context}
    assert schema_request.method == :get
    assert schema_request.url == Fixtures.request_url("notion.data_sources.retrieve")

    assert_receive {:transport_request, query_request, _context}
    assert query_request.method == :post
    assert query_request.url == Fixtures.request_url("notion.data_sources.query")

    connector_event = Enum.at(result.events, 1)

    assert connector_event.payload.schema_context == %{
             context_source: :data_source,
             data_source_id: Fixtures.data_source_id(),
             property_names: ["Status", "Title"],
             resolved_via: [:data_source],
             slot_kinds: [:data_source_filter, :data_source_properties, :data_source_sorts]
           }

    assert [artifact] = result.artifacts
    assert artifact.metadata.schema_context == connector_event.payload.schema_context
  end

  test "rejects notion.data_sources.query before provider invocation when a filter references an unknown property" do
    capability = fetch_capability!("notion.data_sources.query")
    query_url = Fixtures.request_url("notion.data_sources.query")

    input =
      Fixtures.input_for("notion.data_sources.query")
      |> put_in([:filter, :property], "Bogus")

    assert {:error, mapped_error, result} =
             DirectRuntime.execute(
               capability,
               input,
               execution_context("notion.data_sources.query")
             )

    assert_receive {:transport_request, schema_request, _context}
    assert schema_request.method == :get
    assert schema_request.url == Fixtures.request_url("notion.data_sources.retrieve")
    refute_receive {:transport_request, %{url: ^query_url}, _context}

    assert mapped_error.code == "notion.preflight_validation"
    assert mapped_error.class == "invalid_request"
    assert mapped_error.retryability == :terminal
    assert mapped_error.upstream_context.phase == :preflight

    assert mapped_error.upstream_context.issues == [
             %{
               kind: :data_source_filter,
               path: ["filter", "property"],
               property: "Bogus",
               source: :data_source
             }
           ]

    assert Enum.map(result.events, & &1.type) == [
             "attempt.started",
             "connector.notion.data_sources.query.failed",
             "attempt.failed"
           ]
  end

  defp execution_context(capability_id, opts \\ []) do
    Fixtures.execution_context(capability_id,
      notion_client: [
        transport: FixtureTransport,
        transport_opts: [test_pid: self(), response: Keyword.get(opts, :response)]
      ]
    )
  end

  defp legacy_database_parent_response(request, _context) do
    case {request.method, request.url} do
      {:get, page_url} ->
        if page_url == Fixtures.request_url("notion.pages.retrieve") do
          ok_response(legacy_database_parent_page())
        else
          Fixtures.response_for_request(request)
        end

      _other ->
        Fixtures.response_for_request(request)
    end
  end

  defp legacy_database_parent_page do
    Fixtures.output_data("notion.pages.retrieve")
    |> Map.put("parent", %{
      "type" => "database_id",
      "database_id" => Fixtures.database_id()
    })
  end

  defp fetch_capability!(capability_id) do
    Enum.find(Notion.manifest().capabilities, &(&1.id == capability_id)) ||
      raise "missing capability #{capability_id}"
  end

  defp ok_response(body) do
    {:ok,
     %Pristine.Core.Response{
       status: 200,
       headers: %{"content-type" => "application/json"},
       body: Jason.encode!(body)
     }}
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
