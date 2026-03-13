defmodule Jido.Integration.V2.Conformance.SuiteSupport do
  @moduledoc false

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Conformance.CheckResult
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Manifest

  @spec check(String.t() | atom(), boolean(), String.t(), String.t() | nil) :: CheckResult.t()
  def check(id, condition, failure_message, success_message \\ nil)

  def check(id, true, _failure_message, success_message),
    do: CheckResult.pass(id, success_message)

  def check(id, false, failure_message, _success_message),
    do: CheckResult.fail(id, failure_message)

  @spec fetch_capability(Manifest.t(), String.t()) :: Capability.t() | nil
  def fetch_capability(manifest, capability_id) do
    manifest
    |> Map.get(:capabilities, [])
    |> Enum.find(&(&1.id == capability_id))
  end

  @spec declared?(map(), atom()) :: boolean()
  def declared?(map, key) when is_map(map) do
    Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))
  end

  @spec fetch(map(), atom(), term()) :: term()
  def fetch(map, key, default \\ nil), do: Contracts.get(map, key, default)
end
