defmodule Jido.Integration.AgentInterop.PolicyRef do
  @moduledoc """
  Policy and authority references required for generic agent interop.
  """

  alias Jido.Integration.AgentInterop.Validator

  @contract_name "JidoIntegration.AgentInterop.PolicyRef.v1"
  @fields [
    :contract_name,
    :policy_ref,
    :authority_ref,
    :policy_profile_ref,
    :policy_bundle_ref,
    :recovery_owner_ref,
    :metadata
  ]
  @required [:policy_ref, :authority_ref]

  @enforce_keys @required
  defstruct @fields

  @type t :: %__MODULE__{
          contract_name: String.t(),
          policy_ref: String.t(),
          authority_ref: String.t(),
          policy_profile_ref: String.t() | nil,
          policy_bundle_ref: String.t() | nil,
          recovery_owner_ref: String.t() | nil,
          metadata: map()
        }

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = policy_ref), do: normalize(policy_ref)

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
  def to_map(%__MODULE__{} = policy_ref) do
    policy_ref
    |> Map.from_struct()
    |> Validator.compact_dump()
  end

  defp build(attrs) do
    attrs = Validator.attrs!(attrs, @fields, __MODULE__)
    struct!(__MODULE__, Map.take(attrs, @fields))
  end

  defp normalize(%__MODULE__{} = policy_ref) do
    normalized = %__MODULE__{
      policy_ref
      | contract_name: @contract_name,
        policy_ref: Validator.required_string!(policy_ref.policy_ref, :policy_ref),
        authority_ref: Validator.required_string!(policy_ref.authority_ref, :authority_ref),
        policy_profile_ref:
          Validator.optional_string!(policy_ref.policy_profile_ref, :policy_profile_ref),
        policy_bundle_ref:
          Validator.optional_string!(policy_ref.policy_bundle_ref, :policy_bundle_ref),
        recovery_owner_ref:
          Validator.optional_string!(policy_ref.recovery_owner_ref, :recovery_owner_ref),
        metadata: Validator.map!(policy_ref.metadata || %{}, :metadata)
    }

    Validator.reject_raw_secret_material!(normalized.metadata, :metadata)
    {:ok, normalized}
  rescue
    error in ArgumentError -> {:error, error}
  end
end
