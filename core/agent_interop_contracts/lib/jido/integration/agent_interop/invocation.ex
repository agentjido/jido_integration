defmodule Jido.Integration.AgentInterop.Invocation do
  @moduledoc """
  Generic lower-agent invocation envelope.

  Invocation payloads are referenced by `input_ref`; summaries and metadata may
  carry only redacted facts.
  """

  alias Jido.Integration.AgentInterop.Validator

  @contract_name "JidoIntegration.AgentInterop.Invocation.v1"
  @runtime_families [:direct, :session, :process, :http, :jsonrpc, :websocket, :sse, :interop]
  @fields [
    :contract_name,
    :invocation_ref,
    :interop_ref,
    :capability_ref,
    :policy_ref,
    :authority_ref,
    :ledger_ref,
    :idempotency_key,
    :input_ref,
    :input_summary,
    :runtime_family,
    :trace_ref,
    :metadata
  ]
  @required [
    :invocation_ref,
    :interop_ref,
    :capability_ref,
    :policy_ref,
    :authority_ref,
    :ledger_ref,
    :idempotency_key,
    :input_ref,
    :runtime_family
  ]

  @enforce_keys @required
  defstruct @fields

  @type runtime_family ::
          :direct | :session | :process | :http | :jsonrpc | :websocket | :sse | :interop
  @type t :: %__MODULE__{}

  @spec runtime_families() :: [runtime_family()]
  def runtime_families, do: @runtime_families

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = invocation), do: normalize(invocation)

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

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = invocation) do
    invocation
    |> Map.from_struct()
    |> Validator.compact_dump()
  end

  defp build(attrs) do
    attrs = Validator.attrs!(attrs, @fields, __MODULE__)
    struct!(__MODULE__, Map.take(attrs, @fields))
  end

  defp normalize(%__MODULE__{} = invocation) do
    normalized = %__MODULE__{
      invocation
      | contract_name: @contract_name,
        invocation_ref: Validator.required_string!(invocation.invocation_ref, :invocation_ref),
        interop_ref: Validator.required_string!(invocation.interop_ref, :interop_ref),
        capability_ref: Validator.required_string!(invocation.capability_ref, :capability_ref),
        policy_ref: Validator.required_string!(invocation.policy_ref, :policy_ref),
        authority_ref: Validator.required_string!(invocation.authority_ref, :authority_ref),
        ledger_ref: Validator.required_string!(invocation.ledger_ref, :ledger_ref),
        idempotency_key: Validator.required_string!(invocation.idempotency_key, :idempotency_key),
        input_ref: Validator.required_string!(invocation.input_ref, :input_ref),
        input_summary: Validator.map!(invocation.input_summary || %{}, :input_summary),
        runtime_family:
          Validator.enum!(invocation.runtime_family, @runtime_families, :runtime_family),
        trace_ref: Validator.optional_string!(invocation.trace_ref, :trace_ref),
        metadata: Validator.map!(invocation.metadata || %{}, :metadata)
    }

    Validator.reject_raw_secret_material!(normalized.input_summary, :input_summary)
    Validator.reject_raw_secret_material!(normalized.metadata, :metadata)
    {:ok, normalized}
  rescue
    error in ArgumentError -> {:error, error}
  end
end
