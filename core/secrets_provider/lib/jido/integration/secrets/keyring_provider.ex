defmodule Jido.Integration.Secrets.KeyringProvider do
  @moduledoc """
  Production-style keyring provider contract.

  Hosts can back this module with KMS or Vault by supplying a keyring map in
  opts. The contract exposes key IDs, rotation posture, revocation receipts, and
  fail-closed errors without making a cloud integration a package dependency.
  """

  @behaviour Jido.Integration.Secrets.Provider

  alias Jido.Integration.Secrets.SecretHandle

  @dev_key_ids ["dev-local-1", "dev-local-default", "test-local-1"]

  @impl true
  def materialize(lease_ref, scope, opts)
      when is_binary(lease_ref) and is_map(scope) and is_list(opts) do
    with {:ok, key_id} <- key_id(scope, opts),
         :ok <- reject_dev_key_in_production(key_id, opts),
         {:ok, keyring} <- keyring(opts),
         {:ok, material} <- material_for_key(keyring, key_id),
         :ok <- not_revoked?(keyring, key_id) do
      provider_ref = "keyring://#{key_id}"

      SecretHandle.new(
        lease_ref: lease_ref,
        provider_ref: provider_ref,
        audit_ref: audit_ref(%{lease_ref: lease_ref, provider_ref: provider_ref}),
        material: material,
        scope: Map.drop(scope, [:keyring, "keyring"]),
        metadata: %{
          key_id: key_id,
          rotation_posture: rotation_posture(keyring, key_id),
          failure_mode: :fail_closed
        }
      )
    end
  end

  def materialize(_lease_ref, _scope, _opts), do: {:error, :invalid_keyring_secret_request}

  @impl true
  def rotate(binding_ref, opts) when is_binary(binding_ref) and is_list(opts) do
    key_id = Keyword.get(opts, :next_key_id) || "#{binding_ref}:next"

    {:ok,
     %{
       binding_ref: binding_ref,
       next_key_id: key_id,
       rotation_posture: Keyword.get(opts, :rotation_posture, :operator_managed),
       status: :rotation_requested,
       audit_ref: audit_ref(%{binding_ref: binding_ref, next_key_id: key_id, operation: :rotate})
     }}
  end

  @impl true
  def revoke(lease_ref, opts) when is_binary(lease_ref) and is_list(opts) do
    {:ok,
     %{
       lease_ref: lease_ref,
       key_id: Keyword.get(opts, :key_id),
       status: :revoked,
       recovery_owner: Keyword.get(opts, :recovery_owner, :secrets_operator),
       audit_ref: audit_ref(%{lease_ref: lease_ref, operation: :revoke})
     }}
  end

  @impl true
  def audit_ref(%SecretHandle{} = handle), do: handle.audit_ref

  def audit_ref(%{} = attrs) do
    "secret-audit://keyring/#{stable_hash(attrs)}"
  end

  defp key_id(scope, opts) do
    case string_value(scope, :key_id) || string_value(opts, :key_id) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, :missing_key_id}
    end
  end

  defp keyring(opts) do
    case Keyword.get(opts, :keyring) do
      %{} = keyring -> {:ok, keyring}
      _missing -> {:error, :missing_keyring}
    end
  end

  defp material_for_key(keyring, key_id) do
    entries = Map.get(keyring, :entries) || Map.get(keyring, "entries") || %{}

    case Map.get(entries, key_id) do
      %{} = material when map_size(material) > 0 -> {:ok, material}
      _missing -> {:error, {:unknown_key_id, key_id}}
    end
  end

  defp not_revoked?(keyring, key_id) do
    revoked = Map.get(keyring, :revoked_key_ids) || Map.get(keyring, "revoked_key_ids") || []

    if key_id in revoked do
      {:error, {:revoked_key_id, key_id}}
    else
      :ok
    end
  end

  defp rotation_posture(keyring, key_id) do
    postures = Map.get(keyring, :rotation_posture_by_key_id) || %{}
    Map.get(postures, key_id, :operator_managed)
  end

  defp reject_dev_key_in_production(key_id, opts) do
    if production?(opts) and dev_key_id?(key_id) do
      {:error, {:dev_local_key_rejected, key_id}}
    else
      :ok
    end
  end

  defp production?(opts),
    do: Keyword.get(opts, :runtime_env) in [:prod, "prod", :production, "production"]

  defp dev_key_id?(key_id) do
    key_id in @dev_key_ids or String.starts_with?(key_id, "dev-")
  end

  defp string_value(opts, key) when is_list(opts) do
    case Keyword.get(opts, key) do
      value when is_binary(value) -> if value == "", do: nil, else: value
      _other -> nil
    end
  end

  defp string_value(map, key) when is_map(map) do
    case Map.get(map, key) || Map.get(map, Atom.to_string(key)) do
      value when is_binary(value) -> if value == "", do: nil, else: value
      _other -> nil
    end
  end

  defp stable_hash(value) do
    value
    |> inspect(limit: :infinity, printable_limit: :infinity)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
