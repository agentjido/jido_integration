defmodule Jido.Integration.V2.ControlPlane.ReplayNormalizer do
  @moduledoc """
  Bounded replay payload normalization for deterministic runtime replay.
  """

  @runtime_replay_atom_aliases %{
    "actor_id" => :actor_id,
    "allowed_operations" => :allowed_operations,
    "attempt_id" => :attempt_id,
    "base_url" => :base_url,
    "connection_id" => :connection_id,
    "credential_ref" => :credential_ref,
    "credential_ref_id" => :credential_ref_id,
    "environment" => :environment,
    "extensions" => :extensions,
    "fail_attempts" => :fail_attempts,
    "headers" => :headers,
    "input" => :input,
    "lease_id" => :lease_id,
    "messages" => :messages,
    "metadata" => :metadata,
    "model" => :model,
    "model_id" => :model_id,
    "operation" => :operation,
    "options" => :options,
    "profile_id" => :profile_id,
    "prompt" => :prompt,
    "provider" => :provider,
    "run_id" => :run_id,
    "sandbox" => :sandbox,
    "target_id" => :target_id,
    "tenant_id" => :tenant_id,
    "tool_choice" => :tool_choice,
    "tools" => :tools,
    "trace_id" => :trace_id,
    "value" => :value
  }

  @spec aliases() :: %{String.t() => atom()}
  def aliases, do: @runtime_replay_atom_aliases

  @spec alias_keys() :: [String.t()]
  def alias_keys, do: @runtime_replay_atom_aliases |> Map.keys() |> Enum.sort()

  @spec value(term()) :: term()
  def value(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      nested_value = value(nested_value)

      case key do
        key when is_binary(key) ->
          acc
          |> Map.put(key, nested_value)
          |> maybe_put_existing_atom_alias(key, nested_value)

        key when is_atom(key) ->
          acc
          |> Map.put(key, nested_value)
          |> Map.put_new(Atom.to_string(key), nested_value)

        key ->
          Map.put(acc, key, nested_value)
      end
    end)
  end

  def value(value) when is_list(value) do
    Enum.map(value, &value/1)
  end

  def value(value), do: value

  defp maybe_put_existing_atom_alias(map, key, value) when is_binary(key) do
    case Map.get(@runtime_replay_atom_aliases, key) do
      nil -> map
      atom -> Map.put_new(map, atom, value)
    end
  end
end
