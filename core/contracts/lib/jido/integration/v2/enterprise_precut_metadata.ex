defmodule Jido.Integration.V2.EnterprisePrecutMetadataSupport do
  @moduledoc false

  @spec build(module(), String.t(), [atom()], [atom()], map() | keyword(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def build(module, contract_name, fields, required_fields, attrs, opts \\ []) do
    with {:ok, attrs} <- normalize_attrs(attrs),
         [] <- missing_required_fields(attrs, required_fields),
         :ok <- validate_non_neg_integers(attrs, Keyword.get(opts, :non_neg_integer_fields, [])) do
      {:ok, struct(module, attrs |> Map.take(fields) |> Map.put(:contract_name, contract_name))}
    else
      fields when is_list(fields) -> {:error, {:missing_required_fields, fields}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_attrs(attrs) when is_list(attrs), do: {:ok, Map.new(attrs)}

  defp normalize_attrs(attrs) when is_map(attrs) do
    if Map.has_key?(attrs, :__struct__), do: {:ok, Map.from_struct(attrs)}, else: {:ok, attrs}
  end

  defp normalize_attrs(_attrs), do: {:error, :invalid_attrs}

  defp missing_required_fields(attrs, required_fields) do
    Enum.reject(required_fields, &present?(Map.get(attrs, &1)))
  end

  defp validate_non_neg_integers(attrs, fields) do
    if Enum.all?(fields, &(is_integer(Map.get(attrs, &1)) and Map.get(attrs, &1) >= 0)) do
      :ok
    else
      {:error, :invalid_non_negative_integer_field}
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end

defmodule Jido.Integration.V2.LowerSubmissionMetadata do
  @moduledoc "Enterprise pre-cut metadata for lower submissions."

  alias Jido.Integration.V2.EnterprisePrecutMetadataSupport

  @fields [
    :contract_name,
    :tenant_ref,
    :principal_ref,
    :system_actor_ref,
    :resource_ref,
    :workflow_ref,
    :activity_call_ref,
    :authority_packet_ref,
    :permission_decision_ref,
    :trace_id,
    :idempotency_key,
    :dedupe_scope,
    :target_ref,
    :connector_ref,
    :installation_ref,
    :activation_epoch,
    :payload_hash,
    :payload_ref
  ]
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs),
    do:
      EnterprisePrecutMetadataSupport.build(
        __MODULE__,
        "JidoIntegration.LowerSubmissionMetadata.v1",
        @fields,
        [
          :tenant_ref,
          :resource_ref,
          :workflow_ref,
          :activity_call_ref,
          :permission_decision_ref,
          :trace_id,
          :idempotency_key,
          :dedupe_scope,
          :target_ref,
          :installation_ref,
          :activation_epoch,
          :payload_hash
        ],
        attrs,
        non_neg_integer_fields: [:activation_epoch]
      )
end

defmodule Jido.Integration.V2.LowerReadMetadata do
  @moduledoc "Tenant/authority metadata for lower run reads."

  alias Jido.Integration.V2.EnterprisePrecutMetadataSupport

  @fields [
    :contract_name,
    :tenant_ref,
    :actor_ref,
    :resource_ref,
    :lower_run_ref,
    :artifact_ref,
    :permission_decision_ref,
    :trace_id,
    :redaction_posture
  ]
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs),
    do:
      EnterprisePrecutMetadataSupport.build(
        __MODULE__,
        "JidoIntegration.LowerReadMetadata.v1",
        @fields,
        [
          :tenant_ref,
          :actor_ref,
          :resource_ref,
          :permission_decision_ref,
          :trace_id,
          :redaction_posture
        ],
        attrs
      )
end

defmodule Jido.Integration.V2.ArtifactReadMetadata do
  @moduledoc "Tenant/authority metadata for artifact reads."

  alias Jido.Integration.V2.EnterprisePrecutMetadataSupport

  @fields [
    :contract_name,
    :tenant_ref,
    :actor_ref,
    :resource_ref,
    :artifact_ref,
    :permission_decision_ref,
    :trace_id,
    :redaction_posture
  ]
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs),
    do:
      EnterprisePrecutMetadataSupport.build(
        __MODULE__,
        "JidoIntegration.ArtifactReadMetadata.v1",
        @fields,
        [
          :tenant_ref,
          :actor_ref,
          :resource_ref,
          :artifact_ref,
          :permission_decision_ref,
          :trace_id,
          :redaction_posture
        ],
        attrs
      )
end

defmodule Jido.Integration.V2.TargetDescriptorMetadata do
  @moduledoc "Public-safe target descriptor metadata."

  alias Jido.Integration.V2.EnterprisePrecutMetadataSupport

  @fields [:contract_name, :target_ref, :tenant_ref, :resource_ref, :runtime_family, :trace_id]
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs),
    do:
      EnterprisePrecutMetadataSupport.build(
        __MODULE__,
        "JidoIntegration.TargetDescriptorMetadata.v1",
        @fields,
        [:target_ref, :tenant_ref, :resource_ref, :runtime_family, :trace_id],
        attrs
      )
end

defmodule Jido.Integration.V2.ConnectorEffectMetadata do
  @moduledoc "Connector side-effect metadata with installation epoch and idempotency."

  alias Jido.Integration.V2.EnterprisePrecutMetadataSupport

  @fields [
    :contract_name,
    :tenant_ref,
    :connector_ref,
    :installation_ref,
    :activation_epoch,
    :authority_packet_ref,
    :permission_decision_ref,
    :trace_id,
    :idempotency_key,
    :dedupe_scope
  ]
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs),
    do:
      EnterprisePrecutMetadataSupport.build(
        __MODULE__,
        "JidoIntegration.ConnectorEffectMetadata.v1",
        @fields,
        [
          :tenant_ref,
          :connector_ref,
          :installation_ref,
          :activation_epoch,
          :authority_packet_ref,
          :permission_decision_ref,
          :trace_id,
          :idempotency_key,
          :dedupe_scope
        ],
        attrs,
        non_neg_integer_fields: [:activation_epoch]
      )
end

defmodule Jido.Integration.V2.LowerIdempotency do
  @moduledoc "Lower side-effect idempotency and dedupe contract."

  alias Jido.Integration.V2.EnterprisePrecutMetadataSupport

  @fields [
    :contract_name,
    :tenant_ref,
    :idempotency_key,
    :dedupe_scope,
    :side_effect_ref,
    :trace_id
  ]
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs),
    do:
      EnterprisePrecutMetadataSupport.build(
        __MODULE__,
        "JidoIntegration.LowerIdempotency.v1",
        @fields,
        [:tenant_ref, :idempotency_key, :dedupe_scope, :side_effect_ref, :trace_id],
        attrs
      )
end

defmodule Jido.Integration.V2.LowerEventMetadata do
  @moduledoc "Tenant/trace metadata for lower event facts."

  alias Jido.Integration.V2.EnterprisePrecutMetadataSupport

  @fields [
    :contract_name,
    :lower_event_id,
    :tenant_ref,
    :resource_ref,
    :lower_run_ref,
    :workflow_ref,
    :activity_call_ref,
    :trace_id,
    :payload_hash
  ]
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs),
    do:
      EnterprisePrecutMetadataSupport.build(
        __MODULE__,
        "JidoIntegration.LowerEventMetadata.v1",
        @fields,
        [
          :lower_event_id,
          :tenant_ref,
          :resource_ref,
          :lower_run_ref,
          :workflow_ref,
          :activity_call_ref,
          :trace_id,
          :payload_hash
        ],
        attrs
      )
end
