defmodule Jido.Integration.V2.SubmissionAcceptance do
  @moduledoc """
  Durable Spine acceptance receipt for a Brain submission.
  """

  alias Jido.Integration.V2.Contracts

  @contract_version "v1"
  @statuses [:accepted, :duplicate]

  @type status :: :accepted | :duplicate

  @type t :: %__MODULE__{
          contract_version: String.t(),
          submission_key: Contracts.checksum(),
          submission_receipt_ref: String.t(),
          status: status(),
          accepted_at: DateTime.t(),
          ledger_version: non_neg_integer()
        }

  @enforce_keys [
    :contract_version,
    :submission_key,
    :submission_receipt_ref,
    :status,
    :accepted_at,
    :ledger_version
  ]
  defstruct @enforce_keys

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = acceptance), do: normalize(acceptance)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = acceptance) do
    case normalize(acceptance) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = acceptance) do
    %{
      contract_version: acceptance.contract_version,
      submission_key: acceptance.submission_key,
      submission_receipt_ref: acceptance.submission_receipt_ref,
      status: acceptance.status,
      accepted_at: acceptance.accepted_at,
      ledger_version: acceptance.ledger_version
    }
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      contract_version:
        validate_contract_version!(Map.get(attrs, :contract_version, @contract_version)),
      submission_key:
        attrs
        |> fetch!(:submission_key, "submission_acceptance.submission_key")
        |> Contracts.validate_checksum!(),
      submission_receipt_ref:
        attrs
        |> fetch!(:submission_receipt_ref, "submission_acceptance.submission_receipt_ref")
        |> Contracts.validate_non_empty_string!("submission_acceptance.submission_receipt_ref"),
      status: attrs |> fetch!(:status, "submission_acceptance.status") |> validate_status!(),
      accepted_at: Map.get(attrs, :accepted_at, Contracts.now()) |> validate_datetime!(),
      ledger_version:
        attrs
        |> Map.get(:ledger_version, 1)
        |> validate_non_neg_integer!("submission_acceptance.ledger_version")
    }
  end

  defp normalize(%__MODULE__{} = acceptance) do
    {:ok, build!(dump(acceptance))}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_contract_version!(value) when value == @contract_version, do: value

  defp validate_contract_version!(value) do
    raise ArgumentError,
          "submission_acceptance.contract_version must be #{@contract_version}, got: #{inspect(value)}"
  end

  defp validate_status!(value),
    do: Contracts.validate_enum_atomish!(value, @statuses, "submission_acceptance.status")

  defp validate_datetime!(%DateTime{} = value), do: value

  defp validate_datetime!(value) do
    raise ArgumentError,
          "submission_acceptance.accepted_at must be a DateTime, got: #{inspect(value)}"
  end

  defp validate_non_neg_integer!(value, _field_name) when is_integer(value) and value >= 0,
    do: value

  defp validate_non_neg_integer!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a non-negative integer, got: #{inspect(value)}"
  end

  defp fetch!(map, key, field_name), do: Contracts.fetch_required!(map, key, field_name)
end
