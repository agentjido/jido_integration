defmodule Jido.Integration.Auth.Credential do
  @moduledoc """
  Credential struct — represents stored authentication credentials.

  Supports five credential types matching the auth descriptor types:

  - `:oauth2` — access_token + optional refresh_token + expires_at
  - `:api_key` — static key
  - `:service_account` — service account key/JSON
  - `:session_token` — short-lived session token
  - `:webhook_secret` — HMAC signing secret

  Credentials are stored by the Auth.Store and referenced by auth_ref
  strings. Raw credential values never cross process boundaries —
  only auth_refs are passed in envelopes and logs.
  """

  alias Jido.Integration.Error

  @valid_types [:oauth2, :api_key, :service_account, :session_token, :webhook_secret]

  @type credential_type ::
          :oauth2 | :api_key | :service_account | :session_token | :webhook_secret

  @type t :: %__MODULE__{
          type: credential_type(),
          access_token: String.t() | nil,
          refresh_token: String.t() | nil,
          key: String.t() | nil,
          expires_at: DateTime.t() | nil,
          scopes: [String.t()],
          token_semantics: String.t(),
          metadata: map()
        }

  defstruct [
    :type,
    :access_token,
    :refresh_token,
    :key,
    :expires_at,
    scopes: [],
    token_semantics: "none",
    metadata: %{}
  ]

  @doc """
  Create a new credential from a map of attributes.

  ## Required

  - `:type` — one of #{inspect(@valid_types)}

  ## Type-specific requirements

  - `:oauth2` requires `:access_token`
  - `:api_key`, `:service_account`, `:webhook_secret` require `:key`
  - `:session_token` requires `:access_token`
  """
  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_map(attrs) do
    type = Map.get(attrs, :type)

    with :ok <- validate_type(type),
         :ok <- validate_required_for_type(type, attrs) do
      {:ok,
       %__MODULE__{
         type: type,
         access_token: Map.get(attrs, :access_token),
         refresh_token: Map.get(attrs, :refresh_token),
         key: Map.get(attrs, :key),
         expires_at: Map.get(attrs, :expires_at),
         scopes: Map.get(attrs, :scopes, []),
         token_semantics: Map.get(attrs, :token_semantics, "none"),
         metadata: Map.get(attrs, :metadata, %{})
       }}
    end
  end

  @doc "Returns valid credential types."
  @spec valid_types() :: [credential_type()]
  def valid_types, do: @valid_types

  @doc "Check if a credential has expired."
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end

  @doc "Check if a credential can be refreshed (oauth2 with refresh_token)."
  @spec refreshable?(t()) :: boolean()
  def refreshable?(%__MODULE__{type: :oauth2, refresh_token: rt}) when is_binary(rt), do: true
  def refreshable?(%__MODULE__{}), do: false

  @doc """
  Return a copy of the credential with all sensitive fields redacted.
  Safe for logging and telemetry.
  """
  @spec redact(t()) :: t()
  def redact(%__MODULE__{} = cred) do
    %{
      cred
      | access_token: redact_field(cred.access_token),
        refresh_token: redact_field(cred.refresh_token),
        key: redact_field(cred.key)
    }
  end

  @doc "Return the primary secret material for runtime use."
  @spec secret_value(t()) :: String.t() | nil
  def secret_value(%__MODULE__{key: key}) when is_binary(key), do: key

  def secret_value(%__MODULE__{access_token: access_token}) when is_binary(access_token),
    do: access_token

  def secret_value(%__MODULE__{}), do: nil

  defp redact_field(nil), do: nil
  defp redact_field(_), do: "***REDACTED***"

  # Validation

  defp validate_type(type) when type in @valid_types, do: :ok

  defp validate_type(nil),
    do: {:error, Error.new(:invalid_request, "Credential type is required")}

  defp validate_type(type),
    do: {:error, Error.new(:invalid_request, "Invalid credential type: #{inspect(type)}")}

  defp validate_required_for_type(:oauth2, attrs) do
    if Map.has_key?(attrs, :access_token) do
      :ok
    else
      {:error, Error.new(:invalid_request, "OAuth2 credential requires access_token")}
    end
  end

  defp validate_required_for_type(:session_token, attrs) do
    if Map.has_key?(attrs, :access_token) do
      :ok
    else
      {:error, Error.new(:invalid_request, "Session token credential requires access_token")}
    end
  end

  defp validate_required_for_type(type, attrs)
       when type in [:api_key, :service_account, :webhook_secret] do
    if Map.has_key?(attrs, :key) do
      :ok
    else
      {:error, Error.new(:invalid_request, "#{type} credential requires key")}
    end
  end

  defp validate_required_for_type(_type, _attrs), do: :ok
end
