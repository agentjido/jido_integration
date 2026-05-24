defmodule Jido.Integration.ModelInvocation.Receipt do
  @moduledoc """
  Stable model-call receipt emitted by Jido Integration.
  """

  alias Jido.Integration.ModelInvocation.{Canonical, Request, Validation}
  alias Jido.Integration.V2.Contracts

  @schema_version "jido.model_invocation.receipt.v1"

  @enforce_keys [
    :schema_version,
    :receipt_ref,
    :invocation_ref,
    :tenant_ref,
    :status,
    :context_packet_ref,
    :route_decision_ref,
    :prompt_artifact_ref,
    :provider_payload_ref,
    :payload_hash,
    :model_profile_ref,
    :provider_ref,
    :endpoint_ref,
    :runtime_ref,
    :runtime_kind,
    :credential_lease_ref,
    :trace_ref,
    :idempotency_key,
    :token_summary,
    :cost_summary,
    :redaction_class,
    :payload_mode
  ]
  defstruct [
    :schema_version,
    :receipt_ref,
    :invocation_ref,
    :tenant_ref,
    :status,
    :context_packet_ref,
    :route_decision_ref,
    :prompt_artifact_ref,
    :provider_payload_ref,
    :payload_hash,
    :model_profile_ref,
    :provider_ref,
    :endpoint_ref,
    :runtime_ref,
    :runtime_kind,
    :credential_lease_ref,
    :trace_ref,
    :idempotency_key,
    :token_summary,
    :cost_summary,
    :redaction_class,
    :payload_mode,
    output_artifact_ref: nil,
    stream_refs: [],
    failure: nil,
    issued_at: nil,
    completed_at: nil,
    metadata: %{}
  ]

  @type status :: :accepted | :ok | :error | :cancelled

  @type t :: %__MODULE__{
          schema_version: String.t(),
          receipt_ref: String.t(),
          invocation_ref: String.t(),
          tenant_ref: String.t(),
          status: status(),
          context_packet_ref: String.t(),
          route_decision_ref: String.t(),
          prompt_artifact_ref: String.t(),
          provider_payload_ref: String.t(),
          payload_hash: String.t(),
          model_profile_ref: String.t(),
          provider_ref: String.t(),
          endpoint_ref: String.t(),
          runtime_ref: String.t(),
          runtime_kind: String.t(),
          credential_lease_ref: String.t(),
          trace_ref: String.t(),
          idempotency_key: String.t(),
          token_summary: map(),
          cost_summary: map(),
          redaction_class: String.t(),
          payload_mode: String.t(),
          output_artifact_ref: String.t() | nil,
          stream_refs: [String.t()],
          failure: map() | nil,
          issued_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          metadata: map()
        }

  @spec from_request(Request.t(), map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def from_request(%Request{} = request, attrs \\ %{}) do
    attrs = Validation.attrs_map(attrs)

    new(
      Map.merge(
        %{
          invocation_ref: request.invocation_ref,
          tenant_ref: request.tenant_ref,
          context_packet_ref: request.context_packet_ref,
          route_decision_ref: request.route_decision_ref,
          prompt_artifact_ref: request.prompt_artifact_ref,
          provider_payload_ref: request.provider_payload_ref,
          payload_hash: request.payload_hash,
          model_profile_ref: request.model_profile_ref,
          provider_ref: request.provider_ref,
          endpoint_ref: request.endpoint_ref,
          runtime_ref: request.runtime_ref,
          runtime_kind: request.runtime_kind,
          credential_lease_ref: request.credential_lease_ref,
          trace_ref: request.trace_ref,
          idempotency_key: request.idempotency_key,
          redaction_class: request.redaction_class,
          payload_mode: request.payload_mode
        },
        attrs
      )
    )
  end

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = receipt), do: normalize(receipt)

  def new(attrs) do
    attrs
    |> Validation.attrs_map()
    |> build()
    |> normalize()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, receipt} -> receipt
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = receipt) do
    %{
      "schema_version" => receipt.schema_version,
      "receipt_ref" => receipt.receipt_ref,
      "invocation_ref" => receipt.invocation_ref,
      "tenant_ref" => receipt.tenant_ref,
      "status" => receipt.status,
      "context_packet_ref" => receipt.context_packet_ref,
      "route_decision_ref" => receipt.route_decision_ref,
      "prompt_artifact_ref" => receipt.prompt_artifact_ref,
      "provider_payload_ref" => receipt.provider_payload_ref,
      "payload_hash" => receipt.payload_hash,
      "model_profile_ref" => receipt.model_profile_ref,
      "provider_ref" => receipt.provider_ref,
      "endpoint_ref" => receipt.endpoint_ref,
      "runtime_ref" => receipt.runtime_ref,
      "runtime_kind" => receipt.runtime_kind,
      "credential_lease_ref" => receipt.credential_lease_ref,
      "trace_ref" => receipt.trace_ref,
      "idempotency_key" => receipt.idempotency_key,
      "token_summary" => receipt.token_summary,
      "cost_summary" => receipt.cost_summary,
      "redaction_class" => receipt.redaction_class,
      "payload_mode" => receipt.payload_mode,
      "output_artifact_ref" => receipt.output_artifact_ref,
      "stream_refs" => receipt.stream_refs,
      "failure" => receipt.failure,
      "issued_at" => receipt.issued_at,
      "completed_at" => receipt.completed_at,
      "metadata" => receipt.metadata
    }
    |> Contracts.dump_json_safe!()
  end

  @spec canonical_hash(t()) :: String.t()
  def canonical_hash(%__MODULE__{} = receipt), do: receipt |> dump() |> Canonical.checksum!()

  defp build(attrs) do
    base = %__MODULE__{
      schema_version: Contracts.get(attrs, :schema_version, @schema_version),
      receipt_ref: Contracts.get(attrs, :receipt_ref),
      invocation_ref: Validation.required_string!(attrs, :invocation_ref, "invocation_ref"),
      tenant_ref: Validation.required_string!(attrs, :tenant_ref, "tenant_ref"),
      status: attrs |> Contracts.get(:status) |> Validation.status!(),
      context_packet_ref:
        Validation.required_string!(attrs, :context_packet_ref, "context_packet_ref"),
      route_decision_ref:
        Validation.required_string!(attrs, :route_decision_ref, "route_decision_ref"),
      prompt_artifact_ref:
        Validation.required_string!(attrs, :prompt_artifact_ref, "prompt_artifact_ref"),
      provider_payload_ref:
        Validation.required_string!(attrs, :provider_payload_ref, "provider_payload_ref"),
      payload_hash:
        attrs
        |> Validation.required_string!(:payload_hash, "payload_hash")
        |> Validation.checksum!("payload_hash"),
      model_profile_ref:
        Validation.required_string!(attrs, :model_profile_ref, "model_profile_ref"),
      provider_ref: Validation.required_string!(attrs, :provider_ref, "provider_ref"),
      endpoint_ref: Validation.required_string!(attrs, :endpoint_ref, "endpoint_ref"),
      runtime_ref: Validation.required_string!(attrs, :runtime_ref, "runtime_ref"),
      runtime_kind: attrs |> Contracts.get(:runtime_kind) |> Validation.runtime_kind!(),
      credential_lease_ref:
        Validation.required_string!(attrs, :credential_lease_ref, "credential_lease_ref"),
      trace_ref: Validation.required_string!(attrs, :trace_ref, "trace_ref"),
      idempotency_key: Validation.required_string!(attrs, :idempotency_key, "idempotency_key"),
      token_summary: Validation.required_map!(attrs, :token_summary, "token_summary"),
      cost_summary: Validation.required_map!(attrs, :cost_summary, "cost_summary"),
      redaction_class: Validation.required_string!(attrs, :redaction_class, "redaction_class"),
      payload_mode: Validation.required_string!(attrs, :payload_mode, "payload_mode"),
      output_artifact_ref:
        Validation.optional_string!(attrs, :output_artifact_ref, "output_artifact_ref"),
      stream_refs: Validation.optional_list!(attrs, :stream_refs, "stream_refs", []),
      failure: Validation.optional_map!(attrs, :failure, "failure", nil),
      issued_at: Contracts.get(attrs, :issued_at),
      completed_at: Contracts.get(attrs, :completed_at),
      metadata: Validation.optional_map!(attrs, :metadata, "metadata", %{})
    }

    %__MODULE__{base | receipt_ref: base.receipt_ref || derived_receipt_ref(base)}
  end

  defp normalize(%__MODULE__{} = receipt) do
    unless receipt.schema_version == @schema_version do
      raise ArgumentError,
            "schema_version must be #{@schema_version}, got: #{inspect(receipt.schema_version)}"
    end

    Enum.each(receipt.stream_refs, fn stream_ref ->
      Contracts.validate_non_empty_string!(stream_ref, "stream_refs[]")
    end)

    Validation.ensure_no_raw_payloads!(receipt.metadata, "metadata")
    {:ok, receipt}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp derived_receipt_ref(%__MODULE__{} = receipt) do
    value =
      receipt
      |> Map.from_struct()
      |> Map.put(:receipt_ref, nil)

    Canonical.artifact_ref("jido-model-invocation-receipt", value)
  end
end
