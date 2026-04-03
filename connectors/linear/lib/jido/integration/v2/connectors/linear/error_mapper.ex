defmodule Jido.Integration.V2.Connectors.Linear.ErrorMapper do
  @moduledoc false

  alias Jido.Integration.V2.Redaction

  @graphql_mappings %{
    "BAD_USER_INPUT" => %{class: "invalid_request", retryability: :terminal},
    "FORBIDDEN" => %{class: "auth_failed", retryability: :terminal},
    "NOT_FOUND" => %{class: "invalid_request", retryability: :terminal},
    "RATE_LIMITED" => %{class: "rate_limited", retryability: :retryable},
    "UNAUTHENTICATED" => %{class: "auth_failed", retryability: :terminal}
  }

  @spec from_linear_error(LinearSDK.Error.t()) :: map()
  def from_linear_error(%LinearSDK.Error{} = error) do
    provider_code = provider_code(error)
    mapping = mapping(error, provider_code)

    %{
      code: "linear." <> String.downcase(provider_code),
      class: mapping.class,
      retryability: mapping.retryability,
      message: error_message(error, provider_code),
      upstream_context: %{
        http_status: error.status,
        provider_request_id: error.request_id,
        provider_code: provider_code,
        graphql_errors: Redaction.redact(error.graphql_errors),
        body: Redaction.redact(body(error)),
        details: Redaction.redact(error.details)
      }
    }
  end

  @spec from_reason(term()) :: map()
  def from_reason(reason) do
    %{
      code: "linear.internal",
      class: "internal",
      retryability: :fatal,
      message: "Linear operation failed before a provider response was returned",
      upstream_context: %{
        reason: Redaction.redact(reason)
      }
    }
  end

  @spec preflight_validation(String.t(), keyword()) :: map()
  def preflight_validation(message, opts \\ []) when is_binary(message) and is_list(opts) do
    %{
      code: "linear.preflight_validation",
      class: "invalid_request",
      retryability: :terminal,
      message: message,
      upstream_context:
        %{
          phase: :preflight
        }
        |> maybe_put(:issues, Redaction.redact(Keyword.get(opts, :issues)))
    }
  end

  defp provider_code(%LinearSDK.Error{type: :graphql, graphql_errors: [first | _rest]}) do
    first
    |> graphql_provider_code()
    |> case do
      nil -> "GRAPHQL_ERROR"
      code -> code
    end
  end

  defp provider_code(%LinearSDK.Error{type: :transport}), do: "TRANSPORT_ERROR"
  defp provider_code(%LinearSDK.Error{status: 401}), do: "UNAUTHENTICATED"
  defp provider_code(%LinearSDK.Error{status: 403}), do: "FORBIDDEN"
  defp provider_code(%LinearSDK.Error{status: 404}), do: "NOT_FOUND"
  defp provider_code(%LinearSDK.Error{status: 408}), do: "TIMEOUT"
  defp provider_code(%LinearSDK.Error{status: 429}), do: "RATE_LIMITED"

  defp provider_code(%LinearSDK.Error{status: status}) when is_integer(status) and status >= 500,
    do: "HTTP_ERROR"

  defp provider_code(%LinearSDK.Error{type: :http}), do: "HTTP_ERROR"
  defp provider_code(_error), do: "INTERNAL"

  defp mapping(%LinearSDK.Error{type: :transport}, _provider_code) do
    %{class: "unavailable", retryability: :retryable}
  end

  defp mapping(%LinearSDK.Error{status: 408}, _provider_code) do
    %{class: "timeout", retryability: :retryable}
  end

  defp mapping(%LinearSDK.Error{status: 429}, _provider_code) do
    %{class: "rate_limited", retryability: :retryable}
  end

  defp mapping(%LinearSDK.Error{status: status}, _provider_code)
       when is_integer(status) and status >= 500 do
    %{class: "unavailable", retryability: :retryable}
  end

  defp mapping(%LinearSDK.Error{status: 401}, _provider_code) do
    %{class: "auth_failed", retryability: :terminal}
  end

  defp mapping(%LinearSDK.Error{status: 403}, _provider_code) do
    %{class: "auth_failed", retryability: :terminal}
  end

  defp mapping(%LinearSDK.Error{status: 404}, _provider_code) do
    %{class: "invalid_request", retryability: :terminal}
  end

  defp mapping(_error, provider_code) do
    Map.get(@graphql_mappings, provider_code, %{class: "internal", retryability: :fatal})
  end

  defp graphql_provider_code(%{"extensions" => %{"code" => code}}) when is_binary(code), do: code
  defp graphql_provider_code(%{extensions: %{code: code}}) when is_binary(code), do: code
  defp graphql_provider_code(_error), do: nil

  defp error_message(%LinearSDK.Error{} = error, provider_code) do
    base = "[#{String.downcase(provider_code)}] " <> error.message

    if is_binary(error.request_id) and error.request_id != "" do
      base <> " (request_id: #{error.request_id})"
    else
      base
    end
  end

  defp body(%LinearSDK.Error{details: %{body: body}}) when is_map(body), do: body
  defp body(_error), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
