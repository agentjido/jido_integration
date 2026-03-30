defmodule Jido.BoundaryBridge.Error do
  @moduledoc """
  Package-local Splode error family for bridge-facing failures.
  """

  defmodule InvalidRequest do
    @moduledoc false
    use Splode.ErrorClass, class: :invalid_request
  end

  defmodule Resource do
    @moduledoc false
    use Splode.ErrorClass, class: :resource
  end

  defmodule Dependency do
    @moduledoc false
    use Splode.ErrorClass, class: :dependency
  end

  defmodule Timeout do
    @moduledoc false
    use Splode.ErrorClass, class: :timeout
  end

  defmodule Internal do
    @moduledoc false
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false
      use Splode.Error, class: :internal, fields: [:message, :details, :error]
    end
  end

  use Splode,
    error_classes: [
      invalid_request: InvalidRequest,
      resource: Resource,
      dependency: Dependency,
      timeout: Timeout,
      internal: Internal
    ],
    unknown_error: Internal.UnknownError

  defmodule InvalidRequestError do
    @moduledoc "Normalized invalid-request bridge error."

    use Splode.Error,
      class: :invalid_request,
      fields: [:message, :reason, :retryable, :correlation_id, :request_id, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            reason: String.t() | nil,
            retryable: boolean(),
            correlation_id: String.t() | nil,
            request_id: String.t() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Boundary request is invalid")
      |> Keyword.put_new(:retryable, false)
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule ResourceUnavailableError do
    @moduledoc "Normalized resource or unavailable bridge error."

    use Splode.Error,
      class: :resource,
      fields: [:message, :reason, :retryable, :correlation_id, :request_id, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            reason: String.t() | nil,
            retryable: boolean(),
            correlation_id: String.t() | nil,
            request_id: String.t() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Boundary resource is unavailable")
      |> Keyword.put_new(:retryable, true)
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule DependencyFailureError do
    @moduledoc "Normalized dependency bridge error."

    use Splode.Error,
      class: :dependency,
      fields: [:message, :reason, :retryable, :correlation_id, :request_id, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            reason: String.t() | nil,
            retryable: boolean(),
            correlation_id: String.t() | nil,
            request_id: String.t() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Boundary dependency failed")
      |> Keyword.put_new(:retryable, true)
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule TimeoutError do
    @moduledoc "Normalized timeout bridge error."

    use Splode.Error,
      class: :timeout,
      fields: [
        :message,
        :reason,
        :retryable,
        :boundary_session_id,
        :cleanup_outcome,
        :correlation_id,
        :request_id,
        :details
      ]

    @type t :: %__MODULE__{
            message: String.t(),
            reason: String.t() | nil,
            retryable: boolean(),
            boundary_session_id: String.t() | nil,
            cleanup_outcome: :cleaned_up | :unknown | nil,
            correlation_id: String.t() | nil,
            request_id: String.t() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Boundary operation timed out")
      |> Keyword.put_new(:retryable, true)
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule InternalError do
    @moduledoc "Normalized internal bridge error."

    use Splode.Error,
      class: :internal,
      fields: [:message, :reason, :retryable, :correlation_id, :request_id, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            reason: String.t() | nil,
            retryable: boolean(),
            correlation_id: String.t() | nil,
            request_id: String.t() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Boundary bridge failed internally")
      |> Keyword.put_new(:retryable, false)
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  @spec invalid_request(String.t(), keyword()) :: InvalidRequestError.t()
  def invalid_request(message, opts \\ []),
    do: InvalidRequestError.exception(Keyword.put(opts, :message, message))

  @spec resource_unavailable(String.t(), keyword()) :: ResourceUnavailableError.t()
  def resource_unavailable(message, opts \\ []),
    do: ResourceUnavailableError.exception(Keyword.put(opts, :message, message))

  @spec dependency_failure(String.t(), keyword()) :: DependencyFailureError.t()
  def dependency_failure(message, opts \\ []),
    do: DependencyFailureError.exception(Keyword.put(opts, :message, message))

  @spec timeout(String.t(), keyword()) :: TimeoutError.t()
  def timeout(message, opts \\ []),
    do: TimeoutError.exception(Keyword.put(opts, :message, message))

  @spec internal(String.t(), keyword()) :: InternalError.t()
  def internal(message, opts \\ []),
    do: InternalError.exception(Keyword.put(opts, :message, message))
end
