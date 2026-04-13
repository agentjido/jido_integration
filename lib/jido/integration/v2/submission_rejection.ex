defmodule Jido.Integration.V2.SubmissionRejection do
  @moduledoc """
  Typed Spine rejection for a Brain submission.
  """

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.Contracts

  @contract_version "v1"
  @rejection_families [
    :invalid_submission,
    :projection_mismatch,
    :scope_unresolvable,
    :policy_denied,
    :policy_shed,
    :unsupported_target,
    :capacity_exhausted
  ]
  @retry_classes [:never, :after_redecision, :retryable]

  @type rejection_family ::
          :invalid_submission
          | :projection_mismatch
          | :scope_unresolvable
          | :policy_denied
          | :policy_shed
          | :unsupported_target
          | :capacity_exhausted

  @type retry_class :: :never | :after_redecision | :retryable

  @type t :: %__MODULE__{
          contract_version: String.t(),
          submission_key: Contracts.checksum(),
          rejection_family: rejection_family(),
          reason_code: String.t(),
          retry_class: retry_class(),
          redecision_required: boolean(),
          details: map(),
          rejected_at: DateTime.t()
        }

  @enforce_keys [
    :contract_version,
    :submission_key,
    :rejection_family,
    :reason_code,
    :retry_class,
    :redecision_required,
    :details,
    :rejected_at
  ]
  defstruct @enforce_keys

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = rejection), do: normalize(rejection)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = rejection) do
    case normalize(rejection) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = rejection) do
    %{
      contract_version: rejection.contract_version,
      submission_key: rejection.submission_key,
      rejection_family: rejection.rejection_family,
      reason_code: rejection.reason_code,
      retry_class: rejection.retry_class,
      redecision_required: rejection.redecision_required,
      details: rejection.details,
      rejected_at: rejection.rejected_at
    }
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      contract_version:
        validate_contract_version!(Map.get(attrs, :contract_version, @contract_version)),
      submission_key:
        attrs
        |> fetch!(:submission_key, "submission_rejection.submission_key")
        |> Contracts.validate_checksum!(),
      rejection_family:
        attrs
        |> fetch!(:rejection_family, "submission_rejection.rejection_family")
        |> validate_rejection_family!(),
      reason_code:
        attrs
        |> fetch!(:reason_code, "submission_rejection.reason_code")
        |> Contracts.validate_non_empty_string!("submission_rejection.reason_code"),
      retry_class:
        attrs
        |> fetch!(:retry_class, "submission_rejection.retry_class")
        |> validate_retry_class!(),
      redecision_required: validate_boolean!(Map.get(attrs, :redecision_required, false)),
      details: validate_details!(Map.get(attrs, :details, %{})),
      rejected_at: Map.get(attrs, :rejected_at, Contracts.now()) |> validate_datetime!()
    }
  end

  defp normalize(%__MODULE__{} = rejection) do
    {:ok, build!(dump(rejection))}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_contract_version!(value) when value == @contract_version, do: value

  defp validate_contract_version!(value) do
    raise ArgumentError,
          "submission_rejection.contract_version must be #{@contract_version}, got: #{inspect(value)}"
  end

  defp validate_rejection_family!(value),
    do:
      Contracts.validate_enum_atomish!(
        value,
        @rejection_families,
        "submission_rejection.rejection_family"
      )

  defp validate_retry_class!(value),
    do:
      Contracts.validate_enum_atomish!(value, @retry_classes, "submission_rejection.retry_class")

  defp validate_boolean!(value) when is_boolean(value), do: value

  defp validate_boolean!(value),
    do:
      raise(
        ArgumentError,
        "submission_rejection.redecision_required must be boolean, got: #{inspect(value)}"
      )

  defp validate_details!(value) do
    normalized = CanonicalJson.normalize!(value)

    if is_map(normalized) do
      normalized
    else
      raise ArgumentError, "submission_rejection.details must normalize to a JSON object"
    end
  end

  defp validate_datetime!(%DateTime{} = value), do: value

  defp validate_datetime!(value) do
    raise ArgumentError,
          "submission_rejection.rejected_at must be a DateTime, got: #{inspect(value)}"
  end

  defp fetch!(map, key, field_name), do: Contracts.fetch_required!(map, key, field_name)
end
