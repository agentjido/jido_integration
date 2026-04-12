defmodule Jido.Integration.V2.SubmissionIdentity do
  @moduledoc """
  Spine-owned stable identity for a durable Brain submission.
  """

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.Contracts

  @contract_version "v1"
  @submission_families [:invocation, :boundary, :projection, :query]

  @type submission_family :: :invocation | :boundary | :projection | :query

  @type t :: %__MODULE__{
          contract_version: String.t(),
          submission_family: submission_family(),
          tenant_id: String.t(),
          session_id: String.t(),
          request_id: String.t(),
          invocation_request_id: String.t(),
          causal_group_id: String.t(),
          target_id: String.t(),
          target_kind: String.t(),
          selected_step_id: String.t(),
          authority_decision_id: String.t(),
          execution_governance_id: String.t(),
          execution_intent_family: String.t(),
          extensions: map()
        }

  @enforce_keys [
    :contract_version,
    :submission_family,
    :tenant_id,
    :session_id,
    :request_id,
    :invocation_request_id,
    :causal_group_id,
    :target_id,
    :target_kind,
    :selected_step_id,
    :authority_decision_id,
    :execution_governance_id,
    :execution_intent_family,
    :extensions
  ]
  defstruct @enforce_keys

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = identity), do: normalize(identity)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = identity) do
    case normalize(identity) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = identity) do
    %{
      contract_version: identity.contract_version,
      submission_family: identity.submission_family,
      tenant_id: identity.tenant_id,
      session_id: identity.session_id,
      request_id: identity.request_id,
      invocation_request_id: identity.invocation_request_id,
      causal_group_id: identity.causal_group_id,
      target_id: identity.target_id,
      target_kind: identity.target_kind,
      selected_step_id: identity.selected_step_id,
      authority_decision_id: identity.authority_decision_id,
      execution_governance_id: identity.execution_governance_id,
      execution_intent_family: identity.execution_intent_family,
      extensions: identity.extensions
    }
  end

  @spec submission_key(t()) :: Contracts.checksum()
  def submission_key(%__MODULE__{} = identity) do
    identity
    |> dump()
    |> CanonicalJson.checksum!()
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      contract_version:
        validate_contract_version!(Map.get(attrs, :contract_version, @contract_version)),
      submission_family:
        attrs
        |> fetch!(:submission_family, "submission_identity.submission_family")
        |> validate_submission_family!(),
      tenant_id:
        attrs
        |> fetch!(:tenant_id, "submission_identity.tenant_id")
        |> validate_string!("submission_identity.tenant_id"),
      session_id:
        attrs
        |> fetch!(:session_id, "submission_identity.session_id")
        |> validate_string!("submission_identity.session_id"),
      request_id:
        attrs
        |> fetch!(:request_id, "submission_identity.request_id")
        |> validate_string!("submission_identity.request_id"),
      invocation_request_id:
        attrs
        |> fetch!(:invocation_request_id, "submission_identity.invocation_request_id")
        |> validate_string!("submission_identity.invocation_request_id"),
      causal_group_id:
        attrs
        |> fetch!(:causal_group_id, "submission_identity.causal_group_id")
        |> validate_string!("submission_identity.causal_group_id"),
      target_id:
        attrs
        |> fetch!(:target_id, "submission_identity.target_id")
        |> validate_string!("submission_identity.target_id"),
      target_kind:
        attrs
        |> fetch!(:target_kind, "submission_identity.target_kind")
        |> validate_string!("submission_identity.target_kind"),
      selected_step_id:
        attrs
        |> fetch!(:selected_step_id, "submission_identity.selected_step_id")
        |> validate_string!("submission_identity.selected_step_id"),
      authority_decision_id:
        attrs
        |> fetch!(:authority_decision_id, "submission_identity.authority_decision_id")
        |> validate_string!("submission_identity.authority_decision_id"),
      execution_governance_id:
        attrs
        |> fetch!(:execution_governance_id, "submission_identity.execution_governance_id")
        |> validate_string!("submission_identity.execution_governance_id"),
      execution_intent_family:
        attrs
        |> fetch!(:execution_intent_family, "submission_identity.execution_intent_family")
        |> validate_string!("submission_identity.execution_intent_family"),
      extensions: validate_extensions!(Map.get(attrs, :extensions, %{}))
    }
  end

  defp normalize(%__MODULE__{} = identity) do
    {:ok, build!(dump(identity))}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_contract_version!(value) when value == @contract_version, do: value

  defp validate_contract_version!(value) do
    raise ArgumentError,
          "submission_identity.contract_version must be #{@contract_version}, got: #{inspect(value)}"
  end

  defp validate_submission_family!(value) when value in @submission_families, do: value

  defp validate_submission_family!(value) when is_binary(value) do
    case String.to_existing_atom(value) do
      atom when atom in @submission_families -> atom
      _other -> raise ArgumentError
    end
  rescue
    ArgumentError ->
      raise ArgumentError,
            "submission_identity.submission_family must be one of #{inspect(@submission_families)}, got: #{inspect(value)}"
  end

  defp validate_submission_family!(value) do
    raise ArgumentError,
          "submission_identity.submission_family must be one of #{inspect(@submission_families)}, got: #{inspect(value)}"
  end

  defp validate_string!(value, field_name),
    do: Contracts.validate_non_empty_string!(value, field_name)

  defp validate_extensions!(value) do
    normalized = CanonicalJson.normalize!(value)

    if is_map(normalized) do
      normalized
    else
      raise ArgumentError, "submission_identity.extensions must normalize to a JSON object"
    end
  end

  defp fetch!(map, key, field_name) do
    Contracts.fetch!(map, key)
  rescue
    KeyError -> raise ArgumentError, "#{field_name} is required"
  end
end
