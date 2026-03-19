defmodule Jido.Integration.V2.Connectors.GitHub.ErrorMapper do
  @moduledoc false

  alias Jido.Integration.V2.Redaction

  @mappings %{
    api_connection: %{class: "unavailable", retryability: :retryable},
    bad_gateway: %{class: "unavailable", retryability: :retryable},
    conflict: %{class: "invalid_request", retryability: :terminal},
    forbidden: %{class: "auth_failed", retryability: :terminal},
    gateway_timeout: %{class: "timeout", retryability: :retryable},
    invalid_request: %{class: "invalid_request", retryability: :terminal},
    not_found: %{class: "invalid_request", retryability: :terminal},
    rate_limited: %{class: "rate_limited", retryability: :retryable},
    request_timeout: %{class: "timeout", retryability: :retryable},
    response_error: %{class: "internal", retryability: :fatal},
    server_error: %{class: "unavailable", retryability: :retryable},
    service_unavailable: %{class: "unavailable", retryability: :retryable},
    test_env_error: %{class: "internal", retryability: :fatal},
    unauthorized: %{class: "auth_failed", retryability: :terminal},
    unavailable_for_legal_reasons: %{class: "invalid_request", retryability: :terminal},
    unprocessable_entity: %{class: "invalid_request", retryability: :terminal},
    validation: %{class: "invalid_request", retryability: :terminal},
    unknown: %{class: "internal", retryability: :fatal}
  }

  @spec from_github_error(GitHubEx.Error.t()) :: map()
  def from_github_error(%GitHubEx.Error{} = error) do
    code = error.code || :unknown
    mapping = Map.get(@mappings, code, @mappings.unknown)

    %{
      code: "github." <> Atom.to_string(code),
      class: mapping.class,
      retryability: mapping.retryability,
      message: Exception.message(error),
      upstream_context: %{
        http_status: error.status,
        provider_request_id: error.request_id,
        provider_code: Atom.to_string(code),
        retry_after_ms: error.retry_after_ms,
        body: Redaction.redact(error.body),
        headers: Redaction.redact(error.headers),
        additional_data: Redaction.redact(error.additional_data),
        documentation_url: error.documentation_url
      }
    }
  end

  @spec from_reason(term()) :: map()
  def from_reason(:missing_access_token) do
    %{
      code: "github.auth_missing",
      class: "auth_failed",
      retryability: :terminal,
      message: "GitHub lease payload is missing :access_token",
      upstream_context: %{}
    }
  end

  def from_reason({:invalid_repo, value}) do
    %{
      code: "github.invalid_repo",
      class: "invalid_request",
      retryability: :terminal,
      message: "GitHub repo must be in owner/name format",
      upstream_context: %{
        repo: Redaction.redact(value)
      }
    }
  end

  def from_reason({:invalid_input, field, value}) do
    %{
      code: "github.invalid_input",
      class: "invalid_request",
      retryability: :terminal,
      message: "GitHub input #{field} must be a positive integer",
      upstream_context: %{
        field: field,
        value: Redaction.redact(value)
      }
    }
  end

  def from_reason(reason) do
    %{
      code: "github.internal",
      class: "internal",
      retryability: :fatal,
      message: "GitHub operation failed before a provider response was returned",
      upstream_context: %{
        reason: Redaction.redact(reason)
      }
    }
  end
end
