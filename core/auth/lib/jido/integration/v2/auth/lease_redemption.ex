defmodule Jido.Integration.V2.Auth.LeaseRedemption do
  @moduledoc """
  Deterministic credential-lease admissibility checks before materialization.

  This module does not issue leases, resolve raw secrets, or materialize provider
  runtime inputs. It validates a short-lived `CredentialLease` against the
  governed context that wants to redeem it and returns redacted evidence.
  """

  alias Jido.Integration.V2.CredentialLease

  @type rejection_reason ::
          :authority_scope_widening
          | :connector_mismatch
          | :expired_lease
          | :max_calls_exceeded
          | :max_tokens_exceeded
          | :model_not_allowed
          | :network_policy_mismatch
          | :provider_account_mismatch
          | :secret_material_return_forbidden
          | :stale_installation_revision
          | :standalone_context_cannot_govern
          | :tenant_mismatch

  @type evidence :: %{
          required(:lease_id) => String.t(),
          required(:tenant_id) => String.t(),
          required(:credential_ref_id) => String.t(),
          required(:connection_id) => String.t() | nil,
          required(:connector_instance_ref) => String.t() | nil,
          required(:provider_account_ref) => String.t() | nil,
          required(:execution_context_ref) => String.t() | nil,
          required(:authority_ref) => String.t() | nil,
          required(:redacted) => true
        }

  @spec authorize(CredentialLease.t(), map() | keyword()) ::
          {:ok, evidence()} | {:error, rejection_reason()}
  def authorize(%CredentialLease{} = lease, context \\ %{}) do
    context = Map.new(context)

    with :ok <- reject_secret_material_return(context),
         :ok <- ensure_unexpired(lease, context),
         :ok <- ensure_tenant(lease, context),
         :ok <- ensure_context_not_elevated(lease, context),
         :ok <- ensure_authority_not_widened(lease, context),
         :ok <-
           ensure_metadata_match(lease, context, :connector_instance_ref, :connector_mismatch),
         :ok <-
           ensure_metadata_match(
             lease,
             context,
             :provider_account_ref,
             :provider_account_mismatch
           ),
         :ok <- ensure_installation_revision(lease, context),
         :ok <- ensure_max_calls(lease, context),
         :ok <- ensure_max_tokens(lease, context),
         :ok <- ensure_allowed_model(lease, context),
         :ok <- ensure_network_policy(lease, context) do
      {:ok, evidence(lease)}
    end
  end

  @spec constraints_from_context(map() | keyword()) :: map()
  def constraints_from_context(context) do
    context = Map.new(context)

    %{
      max_calls: map_value(context, :max_calls, :unlimited),
      max_tokens: map_value(context, :max_tokens, :unlimited),
      allowed_models: map_value(context, :allowed_models, :any),
      network_policy: map_value(context, :network_policy, :provider_only),
      network_allowlist_refs: map_value(context, :network_allowlist_refs, [])
    }
  end

  @spec redacted_metadata(map() | keyword()) :: map()
  def redacted_metadata(context) do
    context = Map.new(context)

    %{
      connector_instance_ref: optional_string(context, :connector_instance_ref),
      provider_account_ref: optional_string(context, :provider_account_ref),
      execution_context_ref: optional_string(context, :execution_context_ref),
      execution_context_scope: map_value(context, :execution_context_scope),
      authority_ref: optional_string(context, :authority_ref),
      authority_decision_ref: optional_string(context, :authority_decision_ref),
      authority_scope: string_list(map_value(context, :authority_scope, [])),
      installation_revision: optional_scalar(context, :installation_revision),
      constraints: constraints_from_context(context)
    }
    |> drop_empty_values()
  end

  defp reject_secret_material_return(context) do
    if truthy?(map_value(context, :return_secret_material?)) or
         truthy?(map_value(context, :return_secret_material)) do
      {:error, :secret_material_return_forbidden}
    else
      :ok
    end
  end

  defp ensure_unexpired(lease, context) do
    now = map_value(context, :now)

    if match?(%DateTime{}, now) and CredentialLease.expired?(lease, now) do
      {:error, :expired_lease}
    else
      :ok
    end
  end

  defp ensure_tenant(lease, context) do
    case optional_string(context, :tenant_id) do
      nil -> :ok
      tenant_id when tenant_id == lease.tenant_id -> :ok
      _other -> {:error, :tenant_mismatch}
    end
  end

  defp ensure_context_not_elevated(lease, context) do
    lease_scope = metadata_value(lease, :execution_context_scope)
    requested_mode = map_value(context, :requested_authority_mode)

    if lease_scope in [:standalone, "standalone"] and requested_mode in [:governed, "governed"] do
      {:error, :standalone_context_cannot_govern}
    else
      :ok
    end
  end

  defp ensure_authority_not_widened(lease, context) do
    lease_scope = string_list(metadata_value(lease, :authority_scope))
    requested_scope = string_list(map_value(context, :requested_authority_scope, lease_scope))

    if MapSet.subset?(MapSet.new(requested_scope), MapSet.new(lease_scope)) do
      :ok
    else
      {:error, :authority_scope_widening}
    end
  end

  defp ensure_metadata_match(lease, context, key, reason) do
    expected = optional_metadata_string(lease, key)
    actual = optional_string(context, key)

    cond do
      is_nil(expected) or is_nil(actual) -> :ok
      expected == actual -> :ok
      true -> {:error, reason}
    end
  end

  defp ensure_installation_revision(lease, context) do
    expected = metadata_value(lease, :installation_revision)
    actual = map_value(context, :current_installation_revision)

    cond do
      is_nil(expected) or is_nil(actual) -> :ok
      expected == actual -> :ok
      true -> {:error, :stale_installation_revision}
    end
  end

  defp ensure_max_calls(lease, context) do
    case constraint(lease, :max_calls, :unlimited) do
      :unlimited ->
        :ok

      max_calls when is_integer(max_calls) and max_calls >= 0 ->
        if redemption_count(context) < max_calls,
          do: :ok,
          else: {:error, :max_calls_exceeded}

      _other ->
        {:error, :max_calls_exceeded}
    end
  end

  defp ensure_max_tokens(lease, context) do
    case constraint(lease, :max_tokens, :unlimited) do
      :unlimited ->
        :ok

      max_tokens when is_integer(max_tokens) and max_tokens >= 0 ->
        requested_tokens = integer_value(context, :requested_tokens, 0)

        if requested_tokens <= max_tokens,
          do: :ok,
          else: {:error, :max_tokens_exceeded}

      _other ->
        {:error, :max_tokens_exceeded}
    end
  end

  defp ensure_allowed_model(lease, context) do
    allowed_models = constraint(lease, :allowed_models, :any)
    requested_model = optional_string(context, :requested_model)

    cond do
      allowed_models in [:any, "any"] -> :ok
      is_nil(requested_model) -> :ok
      requested_model in string_list(allowed_models) -> :ok
      true -> {:error, :model_not_allowed}
    end
  end

  defp ensure_network_policy(lease, context) do
    policy = network_policy(constraint(lease, :network_policy, :provider_only))
    target = map_value(context, :network_target, :provider)

    case policy do
      :none -> ensure_network_target(target, [:none, "none"])
      :provider_only -> ensure_network_target(target, [:provider, "provider"])
      :provider_plus_allowlist -> ensure_provider_or_allowlisted(lease, context, target)
      :invalid -> {:error, :network_policy_mismatch}
    end
  end

  defp network_policy(policy) when policy in [:none, "none"], do: :none
  defp network_policy(policy) when policy in [:provider_only, "provider_only"], do: :provider_only

  defp network_policy(policy)
       when policy in [:provider_plus_allowlist, "provider_plus_allowlist"],
       do: :provider_plus_allowlist

  defp network_policy(_other), do: :invalid

  defp ensure_network_target(target, valid_targets) do
    if target in valid_targets, do: :ok, else: {:error, :network_policy_mismatch}
  end

  defp ensure_provider_or_allowlisted(_lease, _context, target)
       when target in [:provider, "provider"],
       do: :ok

  defp ensure_provider_or_allowlisted(lease, context, _target) do
    allowlist = string_list(constraint(lease, :network_allowlist_refs, []))
    requested_ref = optional_string(context, :network_target_ref)

    if is_binary(requested_ref) and requested_ref in allowlist,
      do: :ok,
      else: {:error, :network_policy_mismatch}
  end

  defp evidence(%CredentialLease{} = lease) do
    %{
      lease_id: lease.lease_id,
      tenant_id: lease.tenant_id,
      credential_ref_id: lease.credential_ref_id,
      connection_id: lease.connection_id,
      connector_instance_ref: optional_metadata_string(lease, :connector_instance_ref),
      provider_account_ref: optional_metadata_string(lease, :provider_account_ref),
      execution_context_ref: optional_metadata_string(lease, :execution_context_ref),
      authority_ref: optional_metadata_string(lease, :authority_ref),
      redacted: true
    }
    |> drop_empty_values()
  end

  defp constraint(lease, key, default) do
    constraints =
      case metadata_value(lease, :constraints) do
        value when is_map(value) -> value
        _other -> %{}
      end

    map_value(constraints, key, default)
  end

  defp metadata_value(%CredentialLease{metadata: metadata}, key), do: map_value(metadata, key)

  defp optional_metadata_string(lease, key) do
    case metadata_value(lease, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp optional_string(map, key) do
    case map_value(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp optional_scalar(map, key) do
    case map_value(map, key) do
      value when is_binary(value) and value != "" -> value
      value when is_integer(value) -> value
      _other -> nil
    end
  end

  defp string_list(:any), do: :any
  defp string_list("any"), do: :any

  defp string_list(values) when is_list(values) do
    values
    |> Enum.flat_map(fn
      value when is_binary(value) and value != "" -> [value]
      value when is_atom(value) -> [Atom.to_string(value)]
      _other -> []
    end)
    |> Enum.uniq()
  end

  defp string_list(value) when is_binary(value) and value != "", do: [value]
  defp string_list(value) when is_atom(value), do: [Atom.to_string(value)]
  defp string_list(_value), do: []

  defp redemption_count(context), do: integer_value(context, :redemption_count, 0)

  defp integer_value(map, key, default) do
    case map_value(map, key, default) do
      value when is_integer(value) and value >= 0 -> value
      _other -> default
    end
  end

  defp truthy?(value), do: value in [true, "true", "TRUE", 1, "1"]

  defp map_value(map, key, default \\ nil)
  defp map_value(nil, _key, default), do: default

  defp map_value(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp drop_empty_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, [], %{}] end)
    |> Map.new()
  end
end
