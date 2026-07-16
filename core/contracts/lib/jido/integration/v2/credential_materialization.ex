defmodule Jido.Integration.V2.ManagedAccountRef do
  @moduledoc "Secret-free identity and generation fence for one managed provider account."

  @fields [
    :provider_family,
    :account_ref,
    :tenant_id,
    :connection_id,
    :endpoint_ref,
    :quota_scope_ref,
    :generation,
    :fence
  ]
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(%__MODULE__{} = account), do: validate(account)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    account = %__MODULE__{
      provider_family: value(attrs, :provider_family),
      account_ref: value(attrs, :account_ref),
      tenant_id: value(attrs, :tenant_id),
      connection_id: value(attrs, :connection_id),
      endpoint_ref: value(attrs, :endpoint_ref),
      quota_scope_ref: value(attrs, :quota_scope_ref),
      generation: value(attrs, :generation),
      fence: value(attrs, :fence)
    }

    if known_fields?(attrs), do: validate(account), else: {:error, :invalid_managed_account_ref}
  end

  def new(_attrs), do: {:error, :invalid_managed_account_ref}

  def new!(attrs) do
    case new(attrs) do
      {:ok, account} -> account
      {:error, reason} -> raise ArgumentError, Atom.to_string(reason)
    end
  end

  def dump(%__MODULE__{} = account), do: Map.from_struct(account)

  defp validate(%__MODULE__{} = account) do
    strings = Map.take(account, @fields -- [:generation, :fence]) |> Map.values()

    if Enum.all?(strings, &present_string?/1) and positive_integer?(account.generation) and
         non_negative_integer?(account.fence),
       do: {:ok, account},
       else: {:error, :invalid_managed_account_ref}
  end

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp known_fields?(attrs) do
    allowed = MapSet.new(Enum.flat_map(@fields, &[&1, Atom.to_string(&1)]))
    Enum.all?(Map.keys(attrs), &MapSet.member?(allowed, &1))
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0
end

defmodule Jido.Integration.V2.MaterializationRequest do
  @moduledoc """
  Durable-safe request binding a transient credential materialization to one
  exact effect, authority grant, account generation, target, and expiry.
  """

  alias Jido.Integration.V2.ManagedAccountRef

  @fields [
    :materialization_ref,
    :lease_id,
    :account,
    :effect_ref,
    :operation_ref,
    :authority_ref,
    :endpoint_ref,
    :target_ref,
    :issued_at,
    :expires_at
  ]
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    with true <- known_fields?(attrs),
         {:ok, account} <- ManagedAccountRef.new(value(attrs, :account)) do
      request = %__MODULE__{
        materialization_ref: value(attrs, :materialization_ref),
        lease_id: value(attrs, :lease_id),
        account: account,
        effect_ref: value(attrs, :effect_ref),
        operation_ref: value(attrs, :operation_ref),
        authority_ref: value(attrs, :authority_ref),
        endpoint_ref: value(attrs, :endpoint_ref),
        target_ref: value(attrs, :target_ref),
        issued_at: value(attrs, :issued_at),
        expires_at: value(attrs, :expires_at)
      }

      validate(request)
    else
      false -> {:error, :invalid_materialization_request}
      {:error, _reason} = error -> error
    end
  end

  def new(_attrs), do: {:error, :invalid_materialization_request}

  def new!(attrs) do
    case new(attrs) do
      {:ok, request} ->
        request

      {:error, reason} ->
        raise ArgumentError, "invalid materialization request: #{inspect(reason)}"
    end
  end

  def dump(%__MODULE__{} = request) do
    request
    |> Map.from_struct()
    |> Map.update!(:account, &ManagedAccountRef.dump/1)
  end

  @spec valid_for?(t(), ManagedAccountRef.t(), DateTime.t()) :: boolean()
  def valid_for?(%__MODULE__{} = request, %ManagedAccountRef{} = account, %DateTime{} = now) do
    request.account == account and DateTime.compare(request.expires_at, now) == :gt
  end

  defp validate(%__MODULE__{} = request) do
    strings = [
      request.materialization_ref,
      request.lease_id,
      request.effect_ref,
      request.operation_ref,
      request.authority_ref,
      request.endpoint_ref,
      request.target_ref
    ]

    if Enum.all?(strings, &present_string?/1) and is_struct(request.issued_at, DateTime) and
         is_struct(request.expires_at, DateTime) and
         DateTime.compare(request.expires_at, request.issued_at) == :gt do
      {:ok, request}
    else
      {:error, :invalid_materialization_request}
    end
  end

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp known_fields?(attrs) do
    allowed = MapSet.new(Enum.flat_map(@fields, &[&1, Atom.to_string(&1)]))
    Enum.all?(Map.keys(attrs), &MapSet.member?(allowed, &1))
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
end

defmodule Jido.Integration.V2.SecretMaterial do
  @moduledoc "Transient provider-specific secret material that cannot be durably encoded."

  @fields [:materialization_ref, :provider_family, :account_ref, :generation, :payload]
  @derive {Inspect, only: [:materialization_ref, :provider_family, :account_ref, :generation]}
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    material = %__MODULE__{
      materialization_ref: value(attrs, :materialization_ref),
      provider_family: value(attrs, :provider_family),
      account_ref: value(attrs, :account_ref),
      generation: value(attrs, :generation),
      payload: value(attrs, :payload)
    }

    if known_fields?(attrs) and present_string?(material.materialization_ref) and
         present_string?(material.provider_family) and present_string?(material.account_ref) and
         is_integer(material.generation) and material.generation > 0 and is_map(material.payload) and
         map_size(material.payload) > 0 do
      {:ok, material}
    else
      {:error, :invalid_secret_material}
    end
  end

  def new(_attrs), do: {:error, :invalid_secret_material}

  def new!(attrs) do
    case new(attrs) do
      {:ok, material} -> material
      {:error, reason} -> raise ArgumentError, Atom.to_string(reason)
    end
  end

  def redacted(%__MODULE__{} = material) do
    %{
      materialization_ref: material.materialization_ref,
      provider_family: material.provider_family,
      account_ref: material.account_ref,
      generation: material.generation,
      payload: "[REDACTED]"
    }
  end

  defimpl Jason.Encoder do
    def encode(_material, _opts) do
      raise ArgumentError, "secret material is transient and cannot be durably encoded"
    end
  end

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp known_fields?(attrs) do
    allowed = MapSet.new(Enum.flat_map(@fields, &[&1, Atom.to_string(&1)]))
    Enum.all?(Map.keys(attrs), &MapSet.member?(allowed, &1))
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
end

defmodule Jido.Integration.V2.CredentialMaterializer do
  @moduledoc "Provider-family materializer lifecycle. Implementations remain provider-specific."

  @callback materialize(
              Jido.Integration.V2.CredentialLease.t(),
              Jido.Integration.V2.MaterializationRequest.t()
            ) ::
              {:ok, Jido.Integration.V2.SecretMaterial.t()} | {:error, term()}
  @callback revoke(Jido.Integration.V2.SecretMaterial.t(), keyword()) :: :ok | {:error, term()}
end
