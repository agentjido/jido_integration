defmodule Jido.Integration.ModelInvocation.Request do
  @moduledoc """
  Ref-only model invocation request accepted by Jido Integration.
  """

  alias Jido.Integration.ModelInvocation.{Canonical, Validation}
  alias Jido.Integration.V2.{Contracts, InferenceRequest}

  @schema_version "jido.model_invocation.request.v1"

  @enforce_keys [
    :schema_version,
    :invocation_ref,
    :tenant_ref,
    :workflow_ref,
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
    :redaction_class,
    :payload_mode
  ]
  defstruct [
    :schema_version,
    :invocation_ref,
    :tenant_ref,
    :workflow_ref,
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
    :token_budget_ref,
    :cost_budget_ref,
    :redaction_class,
    :payload_mode,
    operation: :generate_text,
    stream?: false,
    issued_at: nil,
    metadata: %{}
  ]

  @type operation :: :generate_text | :stream_text

  @type t :: %__MODULE__{
          schema_version: String.t(),
          invocation_ref: String.t(),
          tenant_ref: String.t(),
          workflow_ref: String.t(),
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
          credential_lease_ref: String.t() | nil,
          trace_ref: String.t(),
          idempotency_key: String.t(),
          token_budget_ref: String.t() | nil,
          cost_budget_ref: String.t() | nil,
          redaction_class: String.t(),
          payload_mode: String.t(),
          operation: operation(),
          stream?: boolean(),
          issued_at: DateTime.t() | nil,
          metadata: map()
        }

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = request), do: normalize(request)

  def new(attrs) do
    attrs = Validation.attrs_map(attrs)
    Validation.ensure_no_raw_payloads!(attrs, "attrs")

    attrs
    |> build()
    |> normalize()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, request} -> request
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = request) do
    %{
      "schema_version" => request.schema_version,
      "invocation_ref" => request.invocation_ref,
      "tenant_ref" => request.tenant_ref,
      "workflow_ref" => request.workflow_ref,
      "context_packet_ref" => request.context_packet_ref,
      "route_decision_ref" => request.route_decision_ref,
      "prompt_artifact_ref" => request.prompt_artifact_ref,
      "provider_payload_ref" => request.provider_payload_ref,
      "payload_hash" => request.payload_hash,
      "model_profile_ref" => request.model_profile_ref,
      "provider_ref" => request.provider_ref,
      "endpoint_ref" => request.endpoint_ref,
      "runtime_ref" => request.runtime_ref,
      "runtime_kind" => request.runtime_kind,
      "credential_lease_ref" => request.credential_lease_ref,
      "trace_ref" => request.trace_ref,
      "idempotency_key" => request.idempotency_key,
      "token_budget_ref" => request.token_budget_ref,
      "cost_budget_ref" => request.cost_budget_ref,
      "redaction_class" => request.redaction_class,
      "payload_mode" => request.payload_mode,
      "operation" => request.operation,
      "stream?" => request.stream?,
      "issued_at" => request.issued_at,
      "metadata" => request.metadata
    }
    |> Contracts.dump_json_safe!()
  end

  @spec canonical_hash(t()) :: String.t()
  def canonical_hash(%__MODULE__{} = request), do: request |> dump() |> Canonical.checksum!()

  @spec to_inference_request(t()) :: InferenceRequest.t()
  def to_inference_request(%__MODULE__{} = request) do
    InferenceRequest.new!(%{
      request_id: request.invocation_ref,
      operation: request.operation,
      messages: [],
      prompt: nil,
      model_preference: %{
        "provider" => provider_atomish(request.provider_ref),
        "model_profile_ref" => request.model_profile_ref
      },
      target_preference: %{
        "endpoint_ref" => request.endpoint_ref,
        "runtime_ref" => request.runtime_ref,
        "runtime_kind" => request.runtime_kind
      },
      stream?: request.stream?,
      metadata: %{
        "tenant_ref" => request.tenant_ref,
        "workflow_ref" => request.workflow_ref,
        "context_packet_ref" => request.context_packet_ref,
        "route_decision_ref" => request.route_decision_ref,
        "prompt_artifact_ref" => request.prompt_artifact_ref,
        "provider_payload_ref" => request.provider_payload_ref,
        "payload_hash" => request.payload_hash,
        "credential_lease_ref" => request.credential_lease_ref,
        "trace_ref" => request.trace_ref,
        "idempotency_key" => request.idempotency_key,
        "redaction_class" => request.redaction_class,
        "payload_mode" => request.payload_mode
      }
    })
  end

  defp build(attrs) do
    runtime_kind = attrs |> Contracts.get(:runtime_kind) |> Validation.runtime_kind!()

    %__MODULE__{
      schema_version: Contracts.get(attrs, :schema_version, @schema_version),
      invocation_ref: Validation.required_string!(attrs, :invocation_ref, "invocation_ref"),
      tenant_ref: Validation.required_string!(attrs, :tenant_ref, "tenant_ref"),
      workflow_ref: Validation.required_string!(attrs, :workflow_ref, "workflow_ref"),
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
      runtime_kind: runtime_kind,
      credential_lease_ref: credential_lease_ref!(attrs, runtime_kind),
      trace_ref: Validation.required_string!(attrs, :trace_ref, "trace_ref"),
      idempotency_key: Validation.required_string!(attrs, :idempotency_key, "idempotency_key"),
      token_budget_ref: Validation.optional_string!(attrs, :token_budget_ref, "token_budget_ref"),
      cost_budget_ref: Validation.optional_string!(attrs, :cost_budget_ref, "cost_budget_ref"),
      redaction_class: Validation.required_string!(attrs, :redaction_class, "redaction_class"),
      payload_mode: Validation.required_string!(attrs, :payload_mode, "payload_mode"),
      operation: attrs |> Contracts.get(:operation) |> Validation.operation!(),
      stream?: Contracts.get(attrs, :stream?, false),
      issued_at: Contracts.get(attrs, :issued_at),
      metadata: Validation.optional_map!(attrs, :metadata, "metadata", %{})
    }
  end

  defp normalize(%__MODULE__{} = request) do
    unless request.schema_version == @schema_version do
      raise ArgumentError,
            "schema_version must be #{@schema_version}, got: #{inspect(request.schema_version)}"
    end

    unless is_boolean(request.stream?) do
      raise ArgumentError, "stream? must be a boolean, got: #{inspect(request.stream?)}"
    end

    Validation.ensure_no_raw_payloads!(request.metadata, "metadata")
    {:ok, request}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp credential_lease_ref!(attrs, "fixture") do
    Validation.optional_string!(attrs, :credential_lease_ref, "credential_lease_ref")
  end

  defp credential_lease_ref!(attrs, _runtime_kind) do
    case Validation.optional_string!(attrs, :credential_lease_ref, "credential_lease_ref") do
      nil ->
        raise ArgumentError, "credential_lease_ref is required for non-fixture runtimes"

      value ->
        value
    end
  end

  defp provider_atomish("provider://" <> rest), do: rest |> String.split("/") |> List.first()
  defp provider_atomish(provider_ref), do: provider_ref
end
