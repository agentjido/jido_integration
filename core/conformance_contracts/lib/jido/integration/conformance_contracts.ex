defmodule Jido.Integration.ConformanceContracts do
  @moduledoc """
  Lightweight connector SDK conformance checks for external authors.
  """

  alias Jido.Integration.V2.Manifest

  @contract_version "connector-sdk.v1"

  @type check_result :: {:ok, map()} | {:error, [term()]}

  @spec validate(module()) :: check_result()
  def validate(connector_module) when is_atom(connector_module) do
    with {:ok, manifest} <- fetch_manifest(connector_module) do
      errors =
        []
        |> require_contract_version(manifest)
        |> require_stable_dump(manifest)
        |> require_deterministic_capabilities(manifest)
        |> require_external_safety(manifest)

      if errors == [] do
        {:ok,
         %{
           connector: manifest.connector,
           contract_version: Manifest.contract_version(manifest),
           manifest_hash: Manifest.canonical_hash(manifest),
           capability_ids: Enum.map(manifest.capabilities, & &1.id)
         }}
      else
        {:error, Enum.reverse(errors)}
      end
    end
  end

  def validate(_connector_module), do: {:error, [:invalid_connector_module]}

  @spec validate!(module()) :: map()
  def validate!(connector_module) do
    case validate(connector_module) do
      {:ok, report} -> report
      {:error, errors} -> raise ArgumentError, "connector conformance failed: #{inspect(errors)}"
    end
  end

  defp fetch_manifest(connector_module) do
    cond do
      not Code.ensure_loaded?(connector_module) ->
        {:error, [:module_not_loaded]}

      not function_exported?(connector_module, :manifest, 0) ->
        {:error, [:missing_manifest_callback]}

      true ->
        case connector_module.manifest() do
          %Manifest{} = manifest -> {:ok, manifest}
          _other -> {:error, [:invalid_manifest]}
        end
    end
  end

  defp require_contract_version(errors, %Manifest{metadata: metadata}) do
    case Map.get(metadata, :contract_version) || Map.get(metadata, "contract_version") do
      @contract_version -> errors
      nil -> [:missing_manifest_version | errors]
      _other -> [:contract_version_mismatch | errors]
    end
  end

  defp require_stable_dump(errors, %Manifest{} = manifest) do
    dump = Manifest.dump(manifest)

    if Manifest.canonical_hash(dump) == Manifest.canonical_hash(manifest) do
      errors
    else
      [:mutable_manifest_dump | errors]
    end
  end

  defp require_deterministic_capabilities(errors, %Manifest{} = manifest) do
    capability_ids = Enum.map(manifest.capabilities, & &1.id)

    if capability_ids == Enum.sort(capability_ids) do
      errors
    else
      [:non_deterministic_capability_order | errors]
    end
  end

  defp require_external_safety(errors, %Manifest{} = manifest) do
    case Manifest.external_safety_errors(manifest) do
      [] -> errors
      safety_errors -> [{:external_safety_errors, safety_errors} | errors]
    end
  end
end

defmodule Jido.Integration.ConformanceContracts.Case do
  @moduledoc """
  ExUnit case template for external companion connector packages.
  """

  defmacro __using__(opts) do
    connector = Keyword.fetch!(opts, :connector)

    quote do
      use ExUnit.Case, async: true

      alias Jido.Integration.ConformanceContracts

      test "connector manifest passes lightweight SDK conformance" do
        assert {:ok, report} =
                 ConformanceContracts.validate(unquote(connector))

        assert report.contract_version == "connector-sdk.v1"
      end
    end
  end
end
