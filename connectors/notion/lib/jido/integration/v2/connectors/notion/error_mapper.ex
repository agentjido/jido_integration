defmodule Jido.Integration.V2.Connectors.Notion.ErrorMapper do
  @moduledoc false

  alias Jido.Integration.V2.Redaction

  @mappings %{
    api_connection: %{class: "unavailable", retryability: :retryable},
    bad_gateway: %{class: "unavailable", retryability: :retryable},
    database_connection_unavailable: %{class: "unavailable", retryability: :retryable},
    gateway_timeout: %{class: "timeout", retryability: :retryable},
    internal_server_error: %{class: "unavailable", retryability: :retryable},
    invalid_client: %{class: "auth_failed", retryability: :terminal},
    invalid_grant: %{class: "auth_failed", retryability: :terminal},
    invalid_json: %{class: "invalid_request", retryability: :terminal},
    invalid_request: %{class: "invalid_request", retryability: :terminal},
    invalid_request_url: %{class: "invalid_request", retryability: :terminal},
    invalid_scope: %{class: "auth_failed", retryability: :terminal},
    missing_version: %{class: "invalid_request", retryability: :terminal},
    object_not_found: %{class: "invalid_request", retryability: :terminal},
    rate_limited: %{class: "rate_limited", retryability: :retryable},
    request_timeout: %{class: "timeout", retryability: :retryable},
    response_error: %{class: "internal", retryability: :fatal},
    restricted_resource: %{class: "auth_failed", retryability: :terminal},
    service_unavailable: %{class: "unavailable", retryability: :retryable},
    test_env_error: %{class: "internal", retryability: :fatal},
    unauthorized: %{class: "auth_failed", retryability: :terminal},
    unauthorized_client: %{class: "auth_failed", retryability: :terminal},
    unsupported_grant_type: %{class: "invalid_request", retryability: :terminal},
    validation: %{class: "invalid_request", retryability: :terminal},
    validation_error: %{class: "invalid_request", retryability: :terminal}
  }

  @spec from_notion_error(NotionSDK.Error.t()) :: map()
  def from_notion_error(%NotionSDK.Error{} = error) do
    code = error.code || :response_error
    mapping = Map.get(@mappings, code, %{class: "internal", retryability: :fatal})

    %{
      code: "notion." <> Atom.to_string(code),
      class: mapping.class,
      retryability: mapping.retryability,
      message: error_message(error),
      upstream_context: %{
        http_status: error.status,
        provider_request_id: error.request_id,
        provider_code: Atom.to_string(code),
        retry_after_ms: error.retry_after_ms,
        body: Redaction.redact(error.body),
        headers: Redaction.redact(error.headers),
        additional_data: Redaction.redact(error.additional_data)
      }
    }
  end

  @spec from_pristine_error(Pristine.Error.t()) :: map()
  def from_pristine_error(%Pristine.Error{} = error) do
    response = Map.get(error, :response)
    body = normalize_map(Map.get(error, :body))
    headers = response_headers(response)
    code = provider_code(body, error.type)

    from_notion_error(
      NotionSDK.Error.new(
        code,
        Map.get(body, "message", Exception.message(error)),
        additional_data: Map.get(body, "additional_data"),
        body: body,
        headers: headers,
        request_id: request_id(body, headers),
        retry_after_ms: retry_after_ms(headers),
        status: Map.get(error, :status)
      )
    )
  end

  @spec from_reason(term()) :: map()
  def from_reason(reason) do
    %{
      code: "notion.internal",
      class: "internal",
      retryability: :fatal,
      message: "Notion operation failed before a provider response was returned",
      upstream_context: %{
        reason: Redaction.redact(reason)
      }
    }
  end

  defp error_message(%NotionSDK.Error{code: :object_not_found}) do
    "Notion could not find the target, or the integration is not shared to it"
  end

  defp error_message(%NotionSDK.Error{} = error) do
    Exception.message(error)
  end

  defp normalize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_map(_value), do: %{}

  defp provider_code(%{"code" => "bad_gateway"}, _type), do: :bad_gateway
  defp provider_code(%{"code" => "conflict_error"}, _type), do: :conflict_error

  defp provider_code(%{"code" => "database_connection_unavailable"}, _type),
    do: :database_connection_unavailable

  defp provider_code(%{"code" => "gateway_timeout"}, _type), do: :gateway_timeout
  defp provider_code(%{"code" => "internal_server_error"}, _type), do: :internal_server_error
  defp provider_code(%{"code" => "invalid_grant"}, _type), do: :invalid_grant
  defp provider_code(%{"code" => "invalid_client"}, _type), do: :invalid_client
  defp provider_code(%{"code" => "invalid_json"}, _type), do: :invalid_json
  defp provider_code(%{"code" => "invalid_request"}, _type), do: :invalid_request
  defp provider_code(%{"code" => "invalid_request_url"}, _type), do: :invalid_request_url
  defp provider_code(%{"code" => "invalid_scope"}, _type), do: :invalid_scope
  defp provider_code(%{"code" => "missing_version"}, _type), do: :missing_version
  defp provider_code(%{"code" => "object_not_found"}, _type), do: :object_not_found
  defp provider_code(%{"code" => "rate_limited"}, _type), do: :rate_limited
  defp provider_code(%{"code" => "restricted_resource"}, _type), do: :restricted_resource
  defp provider_code(%{"code" => "service_unavailable"}, _type), do: :service_unavailable
  defp provider_code(%{"code" => "test_env_error"}, _type), do: :test_env_error
  defp provider_code(%{"code" => "unauthorized"}, _type), do: :unauthorized
  defp provider_code(%{"code" => "unauthorized_client"}, _type), do: :unauthorized_client
  defp provider_code(%{"code" => "unsupported_grant_type"}, _type), do: :unsupported_grant_type
  defp provider_code(%{"code" => "validation_error"}, _type), do: :validation_error
  defp provider_code(_body, :bad_request), do: :invalid_request
  defp provider_code(_body, :authentication), do: :unauthorized
  defp provider_code(_body, :permission_denied), do: :restricted_resource
  defp provider_code(_body, :not_found), do: :object_not_found
  defp provider_code(_body, :conflict), do: :conflict_error
  defp provider_code(_body, :unprocessable_entity), do: :validation_error
  defp provider_code(_body, :rate_limit), do: :rate_limited
  defp provider_code(_body, :internal_server), do: :internal_server_error
  defp provider_code(_body, :timeout), do: :request_timeout
  defp provider_code(_body, :connection), do: :api_connection
  defp provider_code(_body, _type), do: :response_error

  defp request_id(%{"request_id" => request_id}, _headers) when is_binary(request_id),
    do: request_id

  defp request_id(_body, headers) do
    headers["x-request-id"] || headers["X-Request-Id"]
  end

  defp response_headers(%{headers: headers}) when is_map(headers), do: headers
  defp response_headers(%{headers: headers}) when is_list(headers), do: Map.new(headers)
  defp response_headers(_response), do: %{}

  defp retry_after_ms(headers) when is_map(headers) do
    case Map.get(headers, "retry-after") || Map.get(headers, "Retry-After") do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {seconds, ""} -> seconds * 1_000
          _other -> nil
        end

      _other ->
        nil
    end
  end
end
