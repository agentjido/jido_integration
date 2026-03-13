defmodule Jido.Integration.Operation.Envelope do
  @moduledoc """
  Operation envelope — the standardized request wrapper for all
  connector operations.

  Every operation execution passes through an envelope that carries
  the operation ID, arguments, context (trace/span/correlation),
  idempotency key, timeout, and auth reference.
  """

  @type t :: %__MODULE__{
          operation_id: String.t(),
          args: map(),
          context: map(),
          idempotency_key: String.t() | nil,
          timeout_ms: non_neg_integer() | nil,
          auth_ref: String.t() | nil
        }

  @enforce_keys [:operation_id, :args]
  defstruct [
    :operation_id,
    :idempotency_key,
    :timeout_ms,
    :auth_ref,
    args: %{},
    context: %{}
  ]

  @doc """
  Create a new operation envelope.

  ## Options

  - `:context` — trace context map with trace_id, span_id, correlation_id, causation_id
  - `:idempotency_key` — idempotency token for the operation
  - `:timeout_ms` — operation timeout override
  - `:auth_ref` — token reference for authentication
  """
  @spec new(String.t(), map(), keyword()) :: t()
  def new(operation_id, args \\ %{}, opts \\ []) do
    context =
      Keyword.get(opts, :context, %{})
      |> ensure_trace_context()

    %__MODULE__{
      operation_id: operation_id,
      args: args,
      context: context,
      idempotency_key: Keyword.get(opts, :idempotency_key),
      timeout_ms: Keyword.get(opts, :timeout_ms),
      auth_ref: Keyword.get(opts, :auth_ref)
    }
  end

  defp ensure_trace_context(context) do
    Map.merge(
      %{
        "trace_id" => generate_id(),
        "span_id" => generate_id(),
        "correlation_id" => nil,
        "causation_id" => nil
      },
      context
    )
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
