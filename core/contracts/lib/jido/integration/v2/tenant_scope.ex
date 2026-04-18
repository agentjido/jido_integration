defmodule Jido.Integration.V2.TenantScope do
  @moduledoc """
  Typed authorization scope for substrate-facing lower reads.

  Lower records are not public by lower id alone. Callers must provide the
  tenant scope that was authorized at the higher-order substrate boundary.
  """

  alias Jido.Integration.V2.Contracts

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          installation_id: String.t() | nil,
          actor_ref: map() | nil,
          trace_id: String.t() | nil,
          authorized_at: DateTime.t() | nil
        }

  @enforce_keys [:tenant_id]
  defstruct tenant_id: nil,
            installation_id: nil,
            actor_ref: nil,
            trace_id: nil,
            authorized_at: nil

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = scope), do: normalize(scope)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = scope) do
    case normalize(scope) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = scope) do
    %{
      tenant_id: scope.tenant_id,
      installation_id: scope.installation_id,
      actor_ref: scope.actor_ref,
      trace_id: scope.trace_id,
      authorized_at: scope.authorized_at
    }
  end

  defp normalize(%__MODULE__{} = scope) do
    {:ok, build!(dump(scope))}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      tenant_id:
        attrs
        |> Contracts.fetch_required!(:tenant_id, "tenant_scope.tenant_id")
        |> Contracts.validate_non_empty_string!("tenant_scope.tenant_id"),
      installation_id:
        optional_string!(Contracts.get(attrs, :installation_id), "installation_id"),
      actor_ref: optional_actor_ref!(Contracts.get(attrs, :actor_ref)),
      trace_id: optional_string!(Contracts.get(attrs, :trace_id), "trace_id"),
      authorized_at: optional_datetime!(Contracts.get(attrs, :authorized_at))
    }
  end

  defp optional_string!(nil, _field_name), do: nil

  defp optional_string!(value, field_name),
    do: Contracts.validate_non_empty_string!(value, "tenant_scope.#{field_name}")

  defp optional_actor_ref!(nil), do: nil
  defp optional_actor_ref!(actor_ref) when is_map(actor_ref), do: actor_ref

  defp optional_actor_ref!(actor_ref) do
    raise ArgumentError, "tenant_scope.actor_ref must be a map, got: #{inspect(actor_ref)}"
  end

  defp optional_datetime!(nil), do: nil
  defp optional_datetime!(%DateTime{} = authorized_at), do: authorized_at

  defp optional_datetime!(authorized_at) do
    raise ArgumentError,
          "tenant_scope.authorized_at must be a DateTime, got: #{inspect(authorized_at)}"
  end
end
