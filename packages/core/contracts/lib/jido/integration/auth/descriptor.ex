defmodule Jido.Integration.Auth.Descriptor do
  @moduledoc """
  Auth descriptor — declares the authentication requirements for a connector.

  Each connector manifest contains one or more auth descriptors specifying
  what authentication types are supported and how they behave.

  ## Supported Auth Types

  - `api_key` — static API key
  - `oauth2` — OAuth 2.0 authorization code flow
  - `service_account` — service account credentials
  - `session_token` — session-based token
  - `none` — no authentication required
  """

  alias Jido.Integration.Error

  @valid_types ~w(api_key oauth2 service_account session_token none)
  @valid_tenant_bindings ~w(tenant_only tenant_and_workspace global_readonly)

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          display_name: String.t(),
          secret_refs: [String.t()],
          scopes: [String.t()],
          token_semantics: String.t(),
          rotation_policy: map(),
          tenant_binding: String.t(),
          health_check: map(),
          oauth: map() | nil
        }

  @enforce_keys [:id, :type, :display_name]
  defstruct [
    :id,
    :type,
    :display_name,
    :token_semantics,
    :oauth,
    secret_refs: [],
    scopes: [],
    rotation_policy: %{"required" => false, "interval_days" => nil},
    tenant_binding: "tenant_only",
    health_check: %{"enabled" => false, "interval_s" => 3600}
  ]

  @doc """
  Create a new auth descriptor from a map.
  """
  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         :ok <- validate_type(attrs) do
      descriptor = %__MODULE__{
        id: Map.fetch!(attrs, "id"),
        type: Map.fetch!(attrs, "type"),
        display_name: Map.fetch!(attrs, "display_name"),
        secret_refs: Map.get(attrs, "secret_refs", []),
        scopes: Map.get(attrs, "scopes", []),
        token_semantics: Map.get(attrs, "token_semantics", "none"),
        rotation_policy:
          Map.get(attrs, "rotation_policy", %{"required" => false, "interval_days" => nil}),
        tenant_binding: Map.get(attrs, "tenant_binding", "tenant_only"),
        health_check: Map.get(attrs, "health_check", %{"enabled" => false, "interval_s" => 3600}),
        oauth: Map.get(attrs, "oauth")
      }

      {:ok, descriptor}
    end
  end

  @doc "Returns valid auth type values."
  @spec valid_types() :: [String.t()]
  def valid_types, do: @valid_types

  @doc "Returns valid tenant binding values."
  @spec valid_tenant_bindings() :: [String.t()]
  def valid_tenant_bindings, do: @valid_tenant_bindings

  @doc "Serialize to a JSON-encodable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = d) do
    base = %{
      "id" => d.id,
      "type" => d.type,
      "display_name" => d.display_name,
      "secret_refs" => d.secret_refs,
      "scopes" => d.scopes,
      "token_semantics" => d.token_semantics,
      "rotation_policy" => d.rotation_policy,
      "tenant_binding" => d.tenant_binding,
      "health_check" => d.health_check
    }

    if d.oauth do
      Map.put(base, "oauth", d.oauth)
    else
      base
    end
  end

  defp validate_required(attrs) do
    required = ~w(id type display_name)
    missing = Enum.filter(required, &(not Map.has_key?(attrs, &1)))

    if missing == [] do
      :ok
    else
      {:error,
       Error.new(:invalid_request, "Auth descriptor missing: #{Enum.join(missing, ", ")}")}
    end
  end

  defp validate_type(attrs) do
    type = Map.get(attrs, "type")

    if type in @valid_types do
      :ok
    else
      {:error, Error.new(:invalid_request, "Invalid auth type: #{inspect(type)}")}
    end
  end
end
