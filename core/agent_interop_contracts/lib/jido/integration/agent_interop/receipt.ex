defmodule Jido.Integration.AgentInterop.Receipt do
  @moduledoc """
  Normalized runtime receipt emitted for a lower agent effect.
  """

  alias Jido.Integration.AgentInterop.Validator

  @contract_name "JidoIntegration.AgentRuntimeReceipt.v1"
  @runtime_families [:direct, :session, :process, :http, :jsonrpc, :websocket, :sse, :interop]
  @statuses [:started, :streaming, :pending, :succeeded, :failed, :cancelled]
  @terminal_statuses [:succeeded, :failed, :cancelled]
  @transitions %{
    started: [:started, :streaming, :pending, :succeeded, :failed, :cancelled],
    streaming: [:streaming, :pending, :succeeded, :failed, :cancelled],
    pending: [:pending, :streaming, :succeeded, :failed, :cancelled],
    succeeded: [:succeeded],
    failed: [:failed],
    cancelled: [:cancelled]
  }
  @fields [
    :contract_name,
    :receipt_ref,
    :ledger_ref,
    :lower_invocation_ref,
    :runtime_family,
    :capability_ref,
    :authority_ref,
    :idempotency_key,
    :status,
    :output_summary,
    :output_ref,
    :event_seq_hint,
    :evidence_refs,
    :trace_ref,
    :started_at,
    :completed_at,
    :metadata
  ]
  @required [
    :receipt_ref,
    :ledger_ref,
    :lower_invocation_ref,
    :runtime_family,
    :capability_ref,
    :authority_ref,
    :idempotency_key,
    :status
  ]

  @enforce_keys @required
  defstruct @fields

  @type status :: :started | :streaming | :pending | :succeeded | :failed | :cancelled
  @type runtime_family ::
          :direct | :session | :process | :http | :jsonrpc | :websocket | :sse | :interop
  @type t :: %__MODULE__{}

  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @spec terminal_statuses() :: [status()]
  def terminal_statuses, do: @terminal_statuses

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = receipt), do: normalize(receipt)

  def new(attrs) do
    attrs
    |> build()
    |> normalize()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} -> value
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec can_transition?(status() | String.t(), status() | String.t()) :: boolean()
  def can_transition?(from_status, to_status) do
    with {:ok, from_status} <- normalize_status(from_status),
         {:ok, to_status} <- normalize_status(to_status) do
      to_status in Map.fetch!(@transitions, from_status)
    else
      :error -> false
    end
  end

  @spec transition(t(), status() | String.t(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def transition(%__MODULE__{} = receipt, next_status, opts \\ []) do
    next_status = Validator.enum!(next_status, @statuses, :status)

    if can_transition?(receipt.status, next_status) do
      receipt
      |> Map.from_struct()
      |> Map.merge(%{
        status: next_status,
        output_summary: Keyword.get(opts, :output_summary, receipt.output_summary),
        output_ref: Keyword.get(opts, :output_ref, receipt.output_ref),
        evidence_refs: Keyword.get(opts, :evidence_refs, receipt.evidence_refs),
        completed_at: Keyword.get(opts, :completed_at, receipt.completed_at)
      })
      |> new()
    else
      {:error,
       ArgumentError.exception(
         "invalid agent runtime receipt status transition #{receipt.status} -> #{next_status}"
       )}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec transition!(t(), status() | String.t(), keyword()) :: t()
  def transition!(%__MODULE__{} = receipt, next_status, opts \\ []) do
    case transition(receipt, next_status, opts) do
      {:ok, value} -> value
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = receipt) do
    receipt
    |> Map.from_struct()
    |> Validator.compact_dump()
  end

  defp build(attrs) do
    attrs = Validator.attrs!(attrs, @fields, __MODULE__)
    struct!(__MODULE__, Map.take(attrs, @fields))
  end

  defp normalize(%__MODULE__{} = receipt) do
    normalized = %__MODULE__{
      receipt
      | contract_name: @contract_name,
        receipt_ref: Validator.required_string!(receipt.receipt_ref, :receipt_ref),
        ledger_ref: Validator.required_string!(receipt.ledger_ref, :ledger_ref),
        lower_invocation_ref:
          Validator.required_string!(receipt.lower_invocation_ref, :lower_invocation_ref),
        runtime_family:
          Validator.enum!(receipt.runtime_family, @runtime_families, :runtime_family),
        capability_ref: Validator.required_string!(receipt.capability_ref, :capability_ref),
        authority_ref: Validator.required_string!(receipt.authority_ref, :authority_ref),
        idempotency_key: Validator.required_string!(receipt.idempotency_key, :idempotency_key),
        status: Validator.enum!(receipt.status, @statuses, :status),
        output_summary: Validator.map!(receipt.output_summary || %{}, :output_summary),
        output_ref: Validator.optional_string!(receipt.output_ref, :output_ref),
        event_seq_hint: normalize_event_seq_hint!(receipt.event_seq_hint),
        evidence_refs: Validator.string_list!(receipt.evidence_refs || [], :evidence_refs),
        trace_ref: Validator.optional_string!(receipt.trace_ref, :trace_ref),
        started_at: Validator.optional_datetime!(receipt.started_at, :started_at),
        completed_at: Validator.optional_datetime!(receipt.completed_at, :completed_at),
        metadata: Validator.map!(receipt.metadata || %{}, :metadata)
    }

    Validator.reject_raw_secret_material!(normalized.output_summary, :output_summary)
    Validator.reject_raw_secret_material!(normalized.metadata, :metadata)
    {:ok, normalized}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp normalize_status(status) do
    {:ok, Validator.enum!(status, @statuses, :status)}
  rescue
    ArgumentError -> :error
  end

  defp normalize_event_seq_hint!(nil), do: nil
  defp normalize_event_seq_hint!(value) when is_integer(value) and value >= 0, do: value

  defp normalize_event_seq_hint!(value) do
    raise ArgumentError, "event_seq_hint must be a non-negative integer, got: #{inspect(value)}"
  end
end
