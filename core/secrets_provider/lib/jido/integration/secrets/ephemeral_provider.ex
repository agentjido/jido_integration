defmodule Jido.Integration.Secrets.EphemeralProvider do
  @moduledoc """
  Product-command provider for stdin or already materialized ephemeral input.

  The raw value is supplied through a zero-arity materializer function in opts
  and is converted into a short-lived broker handle for a single lower call.
  """

  @behaviour Jido.Integration.Secrets.Provider

  alias Jido.Integration.Secrets.SecretHandle

  @impl true
  def materialize(lease_ref, scope, opts)
      when is_binary(lease_ref) and is_map(scope) and is_list(opts) do
    with {:ok, materializer} <- materializer(opts),
         {:ok, material} <- material(materializer),
         {:ok, material} <- normalize_material(material, scope, opts) do
      provider_ref = string_value(scope, :provider_ref) || "ephemeral://call-scope"

      SecretHandle.new(
        lease_ref: lease_ref,
        provider_ref: provider_ref,
        audit_ref: audit_ref(%{lease_ref: lease_ref, provider_ref: provider_ref}),
        material: material,
        scope: Map.drop(scope, [:material, "material"]),
        metadata: %{source: :ephemeral_call_scope}
      )
    end
  end

  def materialize(_lease_ref, _scope, _opts), do: {:error, :invalid_ephemeral_secret_request}

  @impl true
  def rotate(binding_ref, _opts) when is_binary(binding_ref) do
    {:ok,
     %{
       binding_ref: binding_ref,
       rotation_posture: :not_durable,
       rotated?: false,
       audit_ref: audit_ref(%{binding_ref: binding_ref, operation: :rotate})
     }}
  end

  @impl true
  def revoke(lease_ref, _opts) when is_binary(lease_ref) do
    {:ok,
     %{
       lease_ref: lease_ref,
       status: :expired_with_call_scope,
       audit_ref: audit_ref(%{lease_ref: lease_ref, operation: :revoke})
     }}
  end

  @impl true
  def audit_ref(%SecretHandle{} = handle), do: handle.audit_ref

  def audit_ref(%{} = attrs) do
    "secret-audit://ephemeral/#{stable_hash(attrs)}"
  end

  defp materializer(opts) do
    case Keyword.get(opts, :secret_materializer) || Keyword.get(opts, :credential_materializer) do
      fun when is_function(fun, 0) -> {:ok, fun}
      _missing -> {:error, :missing_secret_materializer}
    end
  end

  defp material(materializer) do
    case materializer.() do
      {:ok, material} -> {:ok, material}
      {:error, reason} -> {:error, reason}
      material -> {:ok, material}
    end
  end

  defp normalize_material(%{} = material, _scope, _opts) when map_size(material) > 0,
    do: {:ok, material}

  defp normalize_material(value, scope, opts) when is_binary(value) and value != "" do
    key = value(scope, :secret_key) || Keyword.get(opts, :secret_key) || :api_key
    {:ok, %{key => value}}
  end

  defp normalize_material(_value, _scope, _opts), do: {:error, :missing_secret_material}

  defp string_value(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp stable_hash(value) do
    value
    |> inspect(limit: :infinity, printable_limit: :infinity)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
