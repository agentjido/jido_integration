defmodule Jido.Integration.V2.Connectors.GitHub.ErrorMapperTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.GitHub.ErrorMapper
  alias Jido.Integration.V2.Redaction

  test "maps GitHubEx.Error values into the redacted Jido taxonomy" do
    error =
      GitHubEx.Error.new(
        :rate_limited,
        "Slow down",
        additional_data: %{"access_token" => "secret-access"},
        body: %{"token" => "secret-access"},
        headers: %{"authorization" => "Bearer secret-access"},
        request_id: "req-github-rate-limit",
        retry_after_ms: 3_000,
        status: 429
      )

    mapped = ErrorMapper.from_github_error(error)

    assert mapped.code == "github.rate_limited"
    assert mapped.class == "rate_limited"
    assert mapped.retryability == :retryable
    assert mapped.message == "[rate_limited] Slow down (request_id: req-github-rate-limit)"
    assert mapped.upstream_context.http_status == 429
    assert mapped.upstream_context.provider_request_id == "req-github-rate-limit"
    assert mapped.upstream_context.provider_code == "rate_limited"
    assert mapped.upstream_context.retry_after_ms == 3_000
    assert mapped.upstream_context.body["token"] == Redaction.redacted()
    assert mapped.upstream_context.headers["authorization"] == Redaction.redacted()
    assert mapped.upstream_context.additional_data["access_token"] == Redaction.redacted()
  end

  test "maps pre-provider failures into an internal connector error and redacts secrets" do
    mapped =
      ErrorMapper.from_reason(%{
        access_token: "secret-access",
        nested: %{refresh_token: "secret-refresh"}
      })

    assert mapped.code == "github.internal"
    assert mapped.class == "internal"
    assert mapped.retryability == :fatal
    assert mapped.message == "GitHub operation failed before a provider response was returned"
    assert mapped.upstream_context.reason.access_token == Redaction.redacted()
    assert mapped.upstream_context.reason.nested.refresh_token == Redaction.redacted()
  end
end
