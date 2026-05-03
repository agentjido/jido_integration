defmodule Jido.Integration.V2.GovernedRuntimeConfig do
  @moduledoc false

  alias Jido.Integration.V2.Contracts

  @governed_context_keys [
    :authority_ref,
    :authority_packet_ref,
    :credential_lease,
    :credential_ref,
    :lease_ref,
    :policy_decision,
    :policy_inputs,
    :run_id,
    :attempt_id,
    :target_descriptor
  ]

  @spec governed_context?(map()) :: boolean()
  def governed_context?(context) when is_map(context) do
    Enum.any?(@governed_context_keys, &present_key?(context, &1))
  end

  def governed_context?(_context), do: false

  @spec standalone_application_opts(map(), atom(), atom() | module(), [atom()]) :: keyword()
  def standalone_application_opts(context, app, key, allowed_keys)
      when is_map(context) and is_atom(app) and is_list(allowed_keys) do
    if governed_context?(context) do
      []
    else
      app
      |> Application.get_env(key, [])
      |> normalize_opts()
      |> Keyword.take(allowed_keys)
    end
  end

  defp present_key?(context, key) do
    case Contracts.get(context, key) do
      nil -> false
      "" -> false
      [] -> false
      %{} = map -> map_size(map) > 0
      _value -> true
    end
  end

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: Enum.into(opts, [])
  defp normalize_opts(_opts), do: []
end
