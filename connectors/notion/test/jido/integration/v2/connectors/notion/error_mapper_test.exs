defmodule Jido.Integration.V2.Connectors.Notion.ErrorMapperTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.Notion.ErrorMapper
  alias Jido.Integration.V2.Redaction

  test "maps NotionSDK.Error values into the redacted Jido taxonomy" do
    error =
      NotionSDK.Error.new(
        :rate_limited,
        "Slow down",
        additional_data: %{"refresh_token" => "secret-refresh"},
        body: %{"access_token" => "secret-access"},
        headers: %{"authorization" => "Bearer secret-access"},
        request_id: "req-notion-rate-limit",
        retry_after_ms: 3_000,
        status: 429
      )

    mapped = ErrorMapper.from_notion_error(error)

    assert mapped.code == "notion.rate_limited"
    assert mapped.class == "rate_limited"
    assert mapped.retryability == :retryable
    assert mapped.message == "[rate_limited] Slow down (request_id: req-notion-rate-limit)"
    assert mapped.upstream_context.http_status == 429
    assert mapped.upstream_context.provider_request_id == "req-notion-rate-limit"
    assert mapped.upstream_context.provider_code == "rate_limited"
    assert mapped.upstream_context.retry_after_ms == 3_000
    assert mapped.upstream_context.body["access_token"] == Redaction.redacted()
    assert mapped.upstream_context.headers["authorization"] == Redaction.redacted()
    assert mapped.upstream_context.additional_data["refresh_token"] == Redaction.redacted()
  end

  test "maps pre-provider failures into an internal connector error and redacts secrets" do
    mapped =
      ErrorMapper.from_reason(%{
        access_token: "secret-access",
        nested: %{refresh_token: "secret-refresh"}
      })

    assert mapped.code == "notion.internal"
    assert mapped.class == "internal"
    assert mapped.retryability == :fatal
    assert mapped.message == "Notion operation failed before a provider response was returned"
    assert mapped.upstream_context.reason.access_token == Redaction.redacted()
    assert mapped.upstream_context.reason.nested.refresh_token == Redaction.redacted()
  end

  test "maps connector preflight validation failures into a distinct invalid-request taxonomy" do
    mapped =
      ErrorMapper.preflight_validation(
        "Notion rejected notion.pages.create during connector preflight schema validation",
        issues: [
          %{
            kind: :data_source_properties,
            path: ["properties", "Bogus"],
            property: "Bogus",
            source: :parent_data_source
          }
        ],
        schema_context: %{
          context_source: :parent_data_source,
          data_source_id: "data-source-123",
          property_names: ["Title"]
        }
      )

    assert mapped.code == "notion.preflight_validation"
    assert mapped.class == "invalid_request"
    assert mapped.retryability == :terminal

    assert mapped.message ==
             "Notion rejected notion.pages.create during connector preflight schema validation"

    assert mapped.upstream_context.phase == :preflight

    assert mapped.upstream_context.issues == [
             %{
               kind: :data_source_properties,
               path: ["properties", "Bogus"],
               property: "Bogus",
               source: :parent_data_source
             }
           ]

    assert mapped.upstream_context.schema_context == %{
             context_source: :parent_data_source,
             data_source_id: "data-source-123",
             property_names: ["Title"]
           }
  end
end
