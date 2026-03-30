defmodule Jido.BoundaryBridge.ErrorNormalizer do
  @moduledoc """
  Pure normalization from adapter and `Jido.Os.TypedError` style failures into
  bridge-facing errors.
  """

  alias Jido.BoundaryBridge.Error

  @typed_error_module Module.concat([Jido, Os, TypedError])

  @spec normalize(term()) :: Exception.t()
  def normalize(%Error.InvalidRequestError{} = error), do: error
  def normalize(%Error.ResourceUnavailableError{} = error), do: error
  def normalize(%Error.DependencyFailureError{} = error), do: error
  def normalize(%Error.TimeoutError{} = error), do: error
  def normalize(%Error.InternalError{} = error), do: error

  def normalize(%ArgumentError{} = error) do
    Error.invalid_request(Exception.message(error),
      reason: "invalid_request",
      retryable: false,
      details: %{cause: %{module: inspect(error.__struct__), message: Exception.message(error)}}
    )
  end

  def normalize(%RuntimeError{} = error) do
    Error.internal(Exception.message(error),
      reason: "internal_error",
      retryable: false,
      details: %{cause: %{module: inspect(error.__struct__), message: Exception.message(error)}}
    )
  end

  def normalize(%{__struct__: @typed_error_module} = error),
    do: normalize_typed_error(Map.from_struct(error))

  def normalize(
        %{error_code: _error_code, category: _category, retryable: _retryable, scope: _scope} =
          error
      ),
      do: normalize_typed_error(error)

  def normalize(other) do
    Error.internal("Boundary bridge received an unknown failure",
      reason: "unknown_error",
      retryable: false,
      details: %{cause: %{module: inspect(Map.get(other, :__struct__)), value: inspect(other)}}
    )
  end

  defp normalize_typed_error(error) do
    reason = to_string(Map.get(error, :error_code))
    category = to_string(Map.get(error, :category))
    retryable = Map.get(error, :retryable, false)
    correlation_id = Map.get(error, :correlation_id)
    request_id = Map.get(error, :request_id)

    details = %{
      cause: %{
        module: "Jido.Os.TypedError",
        reason: reason,
        category: category,
        scope: Map.get(error, :scope),
        details: Map.get(error, :details, %{})
      }
    }

    case category do
      category when category in ["validation", "conflict"] ->
        Error.invalid_request("Boundary request was rejected by the lower boundary",
          reason: reason,
          retryable: retryable,
          correlation_id: correlation_id,
          request_id: request_id,
          details: details
        )

      "unavailable" ->
        Error.resource_unavailable("Boundary capacity or availability is insufficient",
          reason: reason,
          retryable: retryable,
          correlation_id: correlation_id,
          request_id: request_id,
          details: details
        )

      "dependency" ->
        Error.dependency_failure("Boundary dependency failed",
          reason: reason,
          retryable: retryable,
          correlation_id: correlation_id,
          request_id: request_id,
          details: details
        )

      "timeout" ->
        Error.timeout("Boundary operation timed out",
          reason: reason,
          retryable: retryable,
          correlation_id: correlation_id,
          request_id: request_id,
          details: details
        )

      _other ->
        Error.internal("Boundary bridge failed while normalizing a lower-boundary error",
          reason: reason,
          retryable: retryable,
          correlation_id: correlation_id,
          request_id: request_id,
          details: details
        )
    end
  end
end
