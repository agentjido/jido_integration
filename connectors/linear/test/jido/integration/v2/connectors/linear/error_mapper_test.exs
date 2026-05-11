defmodule Jido.Integration.V2.Connectors.Linear.ErrorMapperTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.Linear.ErrorMapper
  alias Jido.Integration.V2.Redaction

  test "maps LinearSDK GraphQL errors into the redacted Jido taxonomy" do
    error = %LinearSDK.Error{
      type: :graphql,
      message: "Issue not found",
      status: 200,
      graphql_errors: [
        %{
          "message" => "Issue not found",
          "extensions" => %{"code" => "NOT_FOUND"},
          "body" => %{"api_key" => "lin_api_secret"}
        }
      ],
      request_id: "req-linear-missing",
      details: %{
        body: %{
          "errors" => [
            %{
              "message" => "Issue not found",
              "extensions" => %{"code" => "NOT_FOUND"},
              "body" => %{"api_key" => "lin_api_secret"}
            }
          ]
        }
      }
    }

    mapped = ErrorMapper.from_linear_error(error)

    assert mapped.code == "linear.not_found"
    assert mapped.class == "invalid_request"
    assert mapped.retryability == :terminal
    assert mapped.message == "[not_found] Issue not found (request_id: req-linear-missing)"
    assert mapped.upstream_context.http_status == 200
    assert mapped.upstream_context.provider_request_id == "req-linear-missing"
    assert mapped.upstream_context.provider_code == "NOT_FOUND"

    assert mapped.upstream_context.graphql_errors == [
             %{
               "message" => "Issue not found",
               "extensions" => %{"code" => "NOT_FOUND"},
               "body" => %{"api_key" => Redaction.redacted()}
             }
           ]

    assert mapped.upstream_context.body["errors"] == [
             %{
               "message" => "Issue not found",
               "extensions" => %{"code" => "NOT_FOUND"},
               "body" => %{"api_key" => Redaction.redacted()}
             }
           ]
  end

  test "maps pre-provider failures into an internal connector error and redacts secrets" do
    mapped =
      ErrorMapper.from_reason(%{
        api_key: "lin_api_secret",
        nested: %{access_token: "lin_oauth_secret"}
      })

    assert mapped.code == "linear.internal"
    assert mapped.class == "internal"
    assert mapped.retryability == :fatal
    assert mapped.message == "Linear operation failed before a provider response was returned"
    assert mapped.upstream_context.reason.api_key == Redaction.redacted()
    assert mapped.upstream_context.reason.nested.access_token == Redaction.redacted()
  end

  test "maps connector preflight validation failures into a distinct invalid-request taxonomy" do
    mapped =
      ErrorMapper.preflight_validation(
        "Linear rejected linear.issues.update because no editable fields were supplied",
        issues: [required_any_of: ["state_id", "title", "description", "assignee_id"]]
      )

    assert mapped.code == "linear.preflight_validation"
    assert mapped.class == "invalid_request"
    assert mapped.retryability == :terminal

    assert mapped.message ==
             "Linear rejected linear.issues.update because no editable fields were supplied"

    assert mapped.upstream_context.phase == :preflight

    assert mapped.upstream_context.issues == [
             required_any_of: ["state_id", "title", "description", "assignee_id"]
           ]
  end

  test "keeps GraphQL, HTTP, transport, and unexpected payload failures distinct" do
    graphql =
      ErrorMapper.from_linear_error(%LinearSDK.Error{
        type: :graphql,
        message: "Provider rejected the query",
        status: 200,
        graphql_errors: [%{"extensions" => %{"code" => "BAD_USER_INPUT"}}],
        request_id: "req-graphql",
        details: %{}
      })

    http =
      ErrorMapper.from_linear_error(%LinearSDK.Error{
        type: :http,
        message: "Linear unavailable",
        status: 503,
        graphql_errors: [],
        request_id: "req-http",
        details: %{}
      })

    transport =
      ErrorMapper.from_linear_error(%LinearSDK.Error{
        type: :transport,
        message: "connect timeout",
        status: nil,
        graphql_errors: [],
        request_id: nil,
        details: %{reason: :timeout}
      })

    unexpected =
      ErrorMapper.unexpected_payload("Linear returned an unexpected payload",
        issues: [data: %{"api_key" => "lin_secret"}]
      )

    assert graphql.code == "linear.bad_user_input"
    assert graphql.class == "invalid_request"
    assert graphql.retryability == :terminal

    assert http.code == "linear.http_error"
    assert http.class == "unavailable"
    assert http.retryability == :retryable
    assert http.upstream_context.http_status == 503

    assert transport.code == "linear.transport_error"
    assert transport.class == "unavailable"
    assert transport.retryability == :retryable

    assert unexpected.code == "linear.unexpected_payload"
    assert unexpected.class == "provider_contract"
    assert unexpected.retryability == :fatal
    assert unexpected.upstream_context.phase == :response_normalization
    assert unexpected.upstream_context.issues[:data]["api_key"] == Redaction.redacted()
  end
end
