defmodule Jido.Integration.Secrets.EnvProvider do
  @moduledoc """
  Local command secrets provider backed by an explicit environment variable.
  """

  @behaviour Jido.Integration.Secrets.Provider

  alias Jido.Integration.Secrets.SecretHandle

  @impl true
  def materialize(lease_ref, scope, opts)
      when is_binary(lease_ref) and is_map(scope) and is_list(opts) do
    with {:ok, env_var} <- env_var(scope, opts),
         {:ok, value} <- env_value(env_var, opts),
         {:ok, secret_key} <- secret_key(scope, opts) do
      SecretHandle.new(
        lease_ref: lease_ref,
        provider_ref: "env://#{env_var}",
        audit_ref: audit_ref(%{lease_ref: lease_ref, provider_ref: "env://#{env_var}"}),
        material: %{secret_key => value},
        scope: Map.drop(scope, [:env, "env"]),
        metadata: %{source: :environment, env_var: env_var}
      )
    end
  end

  def materialize(_lease_ref, _scope, _opts), do: {:error, :invalid_env_secret_request}

  @impl true
  def rotate(binding_ref, opts) when is_binary(binding_ref) and is_list(opts) do
    {:ok,
     %{
       binding_ref: binding_ref,
       provider_ref: "env://operator-managed",
       rotation_posture: :operator_managed,
       rotated?: false,
       audit_ref: audit_ref(%{binding_ref: binding_ref, operation: :rotate})
     }}
  end

  @impl true
  def revoke(lease_ref, opts) when is_binary(lease_ref) and is_list(opts) do
    {:ok,
     %{
       lease_ref: lease_ref,
       status: :revocation_not_supported,
       recovery_owner: Keyword.get(opts, :recovery_owner, :operator),
       audit_ref: audit_ref(%{lease_ref: lease_ref, operation: :revoke})
     }}
  end

  @impl true
  def audit_ref(%SecretHandle{} = handle), do: handle.audit_ref

  def audit_ref(%{} = attrs) do
    "secret-audit://env/#{stable_hash(attrs)}"
  end

  defp env_var(scope, opts) do
    case string_value(scope, :env_var) || string_value(opts, :env_var) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, :missing_secret_env_var}
    end
  end

  defp env_value(env_var, opts) do
    case Keyword.get(opts, :env) do
      env when is_map(env) ->
        case Map.get(env, env_var) do
          value when is_binary(value) and value != "" -> {:ok, value}
          _missing -> {:error, {:missing_secret_env_value, env_var}}
        end

      _missing ->
        {:error, {:missing_secret_env_source, env_var}}
    end
  end

  defp secret_key(scope, opts) do
    case value(scope, :secret_key) || Keyword.get(opts, :secret_key) do
      key when is_atom(key) or is_binary(key) -> {:ok, key}
      _missing -> {:ok, :api_key}
    end
  end

  defp string_value(map, key) when is_map(map) do
    case value(map, key) do
      value when is_binary(value) -> if value == "", do: nil, else: value
      _other -> nil
    end
  end

  defp string_value(opts, key) when is_list(opts) do
    case Keyword.get(opts, key) do
      value when is_binary(value) -> if value == "", do: nil, else: value
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
