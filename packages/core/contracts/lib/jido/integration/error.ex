defmodule Jido.Integration.Error do
  @moduledoc """
  Error taxonomy for the Jido integration platform.

  All errors are classified into one of seven integration error classes,
  each with a default retryability. Connectors MUST use this taxonomy
  for all error responses.

  ## Error Classes

  | Class            | Default Retryability | Description                        |
  |------------------|---------------------|------------------------------------|
  | `invalid_request`| terminal            | Malformed input, won't succeed     |
  | `auth_failed`    | terminal            | Authentication/authorization error |
  | `rate_limited`   | retryable           | Rate limit hit, back off           |
  | `unavailable`    | retryable           | Transient service unavailability   |
  | `timeout`        | retryable           | Operation timed out                |
  | `unsupported`    | terminal            | Operation not available            |
  | `internal`       | fatal               | Unexpected internal error          |

  ## Error Envelope

  Every error includes:
  - `class` — one of the taxonomy values
  - `retryability` — `retryable | terminal | fatal`
  - `message` — human-readable description
  - `code` — dot-separated error code (e.g., `github.rate_limited`)
  - `upstream_context` — opaque, redacted upstream details (never used for policy)
  """

  @type class ::
          :invalid_request
          | :auth_failed
          | :rate_limited
          | :unavailable
          | :timeout
          | :unsupported
          | :internal

  @type retryability :: :retryable | :terminal | :fatal

  @type t :: %__MODULE__{
          class: class(),
          retryability: retryability(),
          message: String.t(),
          code: String.t() | nil,
          upstream_context: map()
        }

  @enforce_keys [:class, :retryability, :message]
  defstruct [:class, :retryability, :message, :code, upstream_context: %{}]

  @class_retryability %{
    invalid_request: :terminal,
    auth_failed: :terminal,
    rate_limited: :retryable,
    unavailable: :retryable,
    timeout: :retryable,
    unsupported: :terminal,
    internal: :fatal
  }

  @valid_classes Map.keys(@class_retryability)

  @doc """
  Create a new error with the given class and message.

  Uses the default retryability for the class unless overridden.

  ## Options

  - `:code` — dot-separated error code
  - `:retryability` — override default retryability
  - `:upstream_context` — opaque upstream error details
  - `:connector_id` — added to code prefix if no code given
  """
  @spec new(class(), String.t(), keyword()) :: t()
  def new(class, message, opts \\ []) when class in @valid_classes do
    retryability = Keyword.get(opts, :retryability, default_retryability(class))
    code = Keyword.get(opts, :code)
    upstream_context = Keyword.get(opts, :upstream_context, %{})

    %__MODULE__{
      class: class,
      retryability: retryability,
      message: message,
      code: code,
      upstream_context: upstream_context
    }
  end

  @doc """
  Returns the default retryability for an error class.
  """
  @spec default_retryability(class()) :: retryability()
  def default_retryability(class) when class in @valid_classes do
    Map.fetch!(@class_retryability, class)
  end

  @doc """
  Returns the list of valid error classes.
  """
  @spec valid_classes() :: [class()]
  def valid_classes, do: @valid_classes

  @doc """
  Returns the class-to-retryability mapping.
  """
  @spec class_retryability_map() :: %{class() => retryability()}
  def class_retryability_map, do: @class_retryability

  @doc """
  Check if a class string matches taxonomy defaults for retryability.
  """
  @spec valid_retryability?(String.t(), String.t()) :: boolean()
  def valid_retryability?(class_str, retryability_str) do
    class = safe_to_atom(class_str)
    retryability = safe_to_atom(retryability_str)

    case Map.get(@class_retryability, class) do
      nil -> false
      expected -> expected == retryability
    end
  end

  @doc """
  Returns a human-readable message for the error.
  """
  @spec message(t()) :: String.t()
  def message(%__MODULE__{message: msg, code: nil}), do: msg
  def message(%__MODULE__{message: msg, code: code}), do: "[#{code}] #{msg}"

  @doc """
  Returns true if the error is retryable.
  """
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{retryability: :retryable}), do: true
  def retryable?(%__MODULE__{}), do: false

  @doc """
  Returns true if the error is terminal (won't succeed on retry).
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{retryability: :terminal}), do: true
  def terminal?(%__MODULE__{}), do: false

  @doc """
  Returns true if the error is fatal (unexpected, system-level).
  """
  @spec fatal?(t()) :: boolean()
  def fatal?(%__MODULE__{retryability: :fatal}), do: true
  def fatal?(%__MODULE__{}), do: false

  defp safe_to_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  defp safe_to_atom(atom) when is_atom(atom), do: atom

  defimpl Jason.Encoder do
    def encode(error, opts) do
      map = %{
        "class" => to_string(error.class),
        "retryability" => to_string(error.retryability),
        "message" => error.message,
        "code" => error.code,
        "upstream_context" => error.upstream_context
      }

      Jason.Encode.map(map, opts)
    end
  end
end
