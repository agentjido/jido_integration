defmodule Jido.BoundaryBridge.ErrorNormalizerTest do
  use ExUnit.Case, async: true

  alias Jido.BoundaryBridge.Error
  alias Jido.BoundaryBridge.ErrorNormalizer

  @typed_error Module.concat([Jido, Os, TypedError])

  test "maps capacity and unavailable typed errors into resource errors" do
    error =
      ErrorNormalizer.normalize(%{
        __struct__: @typed_error,
        error_code: "sandbox_capacity_exhausted",
        category: "unavailable",
        retryable: true,
        scope: "instance",
        details: %{backend_kind: "sprites"},
        correlation_id: "corr-capacity",
        request_id: "req-capacity"
      })

    assert %Error.ResourceUnavailableError{} = error
    assert error.reason == "sandbox_capacity_exhausted"
    assert error.retryable == true
    assert error.correlation_id == "corr-capacity"
    assert error.request_id == "req-capacity"
    assert error.details.cause.category == "unavailable"
  end

  test "maps validation typed errors into invalid-request errors" do
    error =
      ErrorNormalizer.normalize(%{
        __struct__: @typed_error,
        error_code: "sandbox_request_invalid",
        category: "validation",
        retryable: false,
        scope: "instance",
        details: %{field: "target_id"},
        correlation_id: "corr-invalid",
        request_id: "req-invalid"
      })

    assert %Error.InvalidRequestError{} = error
    assert error.reason == "sandbox_request_invalid"
    assert error.retryable == false
    assert error.details.cause.scope == "instance"
  end

  test "maps dependency typed errors into dependency failures" do
    error =
      ErrorNormalizer.normalize(%{
        __struct__: @typed_error,
        error_code: "sandbox_backend_dependency_failed",
        category: "dependency",
        retryable: true,
        scope: "instance",
        details: %{backend_kind: "sprites"},
        correlation_id: "corr-dependency",
        request_id: "req-dependency"
      })

    assert %Error.DependencyFailureError{} = error
    assert error.reason == "sandbox_backend_dependency_failed"
    assert error.retryable == true
    assert error.correlation_id == "corr-dependency"
  end

  test "preserves causal-chain metadata from typed errors when available" do
    error =
      ErrorNormalizer.normalize(%{
        __struct__: @typed_error,
        error_code: "sandbox_backend_dependency_failed",
        category: "dependency",
        retryable: true,
        scope: "instance",
        details: %{
          cause: %{reason: "lower_boundary_failed"},
          causes: [%{reason: "transport_attach_failed"}],
          underlying: %{module: "Lower.Boundary.Error", message: "socket closed"}
        },
        correlation_id: "corr-causes",
        request_id: "req-causes"
      })

    assert %Error.DependencyFailureError{} = error
    assert error.details.causes == [%{reason: "transport_attach_failed"}]
    assert error.details.underlying == %{module: "Lower.Boundary.Error", message: "socket closed"}
    assert error.details.cause.details.cause == %{reason: "lower_boundary_failed"}
  end
end
