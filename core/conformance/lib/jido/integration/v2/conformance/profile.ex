defmodule Jido.Integration.V2.Conformance.Profile do
  @moduledoc false

  @type suite_id ::
          :manifest_contract
          | :capability_contracts
          | :runtime_class_fit
          | :policy_contract
          | :deterministic_fixtures
          | :ingress_definition_discipline

  @type name :: :connector_foundation

  @enforce_keys [:name, :description, :suite_ids]
  defstruct [:name, :description, :suite_ids]

  @type t :: %__MODULE__{
          name: name(),
          description: String.t(),
          suite_ids: [suite_id()]
        }

  @spec default() :: t()
  def default, do: Map.fetch!(profiles_map(), :connector_foundation)

  @spec names() :: [name()]
  def names do
    profiles_map()
    |> Map.keys()
    |> Enum.sort()
  end

  @spec fetch(name() | String.t()) :: {:ok, t()} | :error
  def fetch(name) do
    case normalize_name(name) do
      {:ok, normalized_name} -> Map.fetch(profiles_map(), normalized_name)
      :error -> :error
    end
  end

  defp normalize_name(name) when is_atom(name) do
    if Map.has_key?(profiles_map(), name), do: {:ok, name}, else: :error
  end

  defp normalize_name(name) when is_binary(name) do
    case Enum.find(names(), &(Atom.to_string(&1) == name)) do
      nil -> :error
      normalized_name -> {:ok, normalized_name}
    end
  end

  defp normalize_name(_name), do: :error

  defp profiles_map do
    %{
      connector_foundation: %__MODULE__{
        name: :connector_foundation,
        description:
          "Base deterministic connector conformance for manifest, runtime-fit, policy, fixtures, and ingress discipline",
        suite_ids: [
          :manifest_contract,
          :capability_contracts,
          :runtime_class_fit,
          :policy_contract,
          :deterministic_fixtures,
          :ingress_definition_discipline
        ]
      }
    }
  end
end
