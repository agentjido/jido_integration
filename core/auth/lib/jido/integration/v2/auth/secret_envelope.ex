defmodule Jido.Integration.V2.Auth.SecretEnvelope do
  @moduledoc false

  @default_key_id "dev-local-1"
  @default_key Base.encode64(:crypto.hash(:sha256, "jido_integration_v2_auth_dev_key"))
  @format "json-v1"
  @cipher :aes_256_gcm
  @iv_bytes 12
  @aad_prefix "jido.integration.v2.auth"
  @known_atom_keys [
    :access_token,
    :api_key,
    :client_secret,
    :private_key,
    :refresh_token,
    :webhook_secret
  ]
  @known_atom_key_lookup Map.new(@known_atom_keys, &{Atom.to_string(&1), &1})

  @spec encrypt(term(), String.t()) :: map()
  def encrypt(value, aad_suffix) do
    %{active_kid: kid, keys: keys} = keyring()
    key = key!(keys, kid)
    iv = :crypto.strong_rand_bytes(@iv_bytes)
    aad = aad(aad_suffix)
    plaintext = encode_payload!(value)

    {ciphertext, tag} = :crypto.crypto_one_time_aead(@cipher, key, iv, plaintext, aad, true)

    %{
      "alg" => "A256GCM",
      "format" => @format,
      "kid" => kid,
      "iv" => Base.encode64(iv),
      "ciphertext" => Base.encode64(ciphertext),
      "tag" => Base.encode64(tag)
    }
  end

  @spec decrypt(map(), String.t()) :: term()
  def decrypt(envelope, aad_suffix) when is_map(envelope) do
    kid = Map.fetch!(envelope, "kid")
    key = key!(keyring().keys, kid)
    iv = decode!(envelope, "iv")
    ciphertext = decode!(envelope, "ciphertext")
    tag = decode!(envelope, "tag")
    aad = aad(aad_suffix)

    plaintext = :crypto.crypto_one_time_aead(@cipher, key, iv, ciphertext, aad, tag, false)
    decode_payload!(Map.fetch!(envelope, "format"), plaintext)
  end

  @spec keyring() :: %{active_kid: String.t(), keys: map()}
  def keyring do
    case Application.get_env(:jido_integration_v2_auth, :keyring) do
      nil ->
        reject_default_keyring_in_production!()
        %{active_kid: @default_key_id, keys: %{@default_key_id => @default_key}}

      %{} = keyring ->
        keyring
    end
  end

  defp aad(suffix), do: "#{@aad_prefix}:#{suffix}"

  defp reject_default_keyring_in_production! do
    if Application.get_env(:jido_integration_v2_auth, :runtime_env) in [
         :prod,
         "prod",
         :production,
         "production"
       ] do
      raise ArgumentError,
            "jido auth production configuration requires an explicit non-default keyring"
    end
  end

  defp key!(keys, kid) do
    keys
    |> Map.fetch!(kid)
    |> normalize_key!()
  end

  defp normalize_key!(key) when is_binary(key) do
    case Base.decode64(key) do
      {:ok, decoded} when byte_size(decoded) in [16, 24, 32] ->
        decoded

      _ when byte_size(key) in [16, 24, 32] ->
        key

      _ ->
        raise ArgumentError, "invalid auth encryption key material"
    end
  end

  defp decode!(envelope, key) do
    envelope
    |> Map.fetch!(key)
    |> Base.decode64!()
  end

  defp encode_payload!(value) do
    value
    |> encode_value!()
    |> Jason.encode!()
  end

  defp decode_payload!(@format, plaintext) do
    plaintext
    |> Jason.decode!()
    |> decode_value!()
  end

  defp decode_payload!(format, _plaintext) do
    raise ArgumentError, "unsupported auth secret envelope format #{inspect(format)}"
  end

  defp encode_value!(%{} = map) do
    %{
      "type" => "map",
      "entries" =>
        Enum.map(map, fn {key, value} ->
          %{"key" => encode_key!(key), "value" => encode_value!(value)}
        end)
    }
  end

  defp encode_value!(list) when is_list(list) do
    %{"type" => "list", "items" => Enum.map(list, &encode_value!/1)}
  end

  defp encode_value!(value)
       when is_binary(value) or is_integer(value) or is_float(value) or is_boolean(value) or
              is_nil(value) do
    %{"type" => "scalar", "value" => value}
  end

  defp encode_value!(value) when is_atom(value) do
    %{"type" => "atom", "value" => Atom.to_string(value)}
  end

  defp encode_value!(value) do
    raise ArgumentError, "unsupported auth secret envelope value #{inspect(value)}"
  end

  defp decode_value!(%{"type" => "map", "entries" => entries}) when is_list(entries) do
    Map.new(entries, fn %{"key" => key, "value" => value} ->
      {decode_key!(key), decode_value!(value)}
    end)
  end

  defp decode_value!(%{"type" => "list", "items" => items}) when is_list(items) do
    Enum.map(items, &decode_value!/1)
  end

  defp decode_value!(%{"type" => "scalar", "value" => value}), do: value

  defp decode_value!(%{"type" => "atom", "value" => value}) when is_binary(value) do
    Map.get(@known_atom_key_lookup, value, value)
  end

  defp decode_value!(value) do
    raise ArgumentError, "invalid auth secret envelope payload #{inspect(value)}"
  end

  defp encode_key!(key) when is_atom(key), do: %{"type" => "atom", "value" => Atom.to_string(key)}
  defp encode_key!(key) when is_binary(key), do: %{"type" => "string", "value" => key}

  defp encode_key!(key) do
    raise ArgumentError, "unsupported auth secret envelope key #{inspect(key)}"
  end

  defp decode_key!(%{"type" => "atom", "value" => value}) when is_binary(value) do
    Map.get(@known_atom_key_lookup, value, value)
  end

  defp decode_key!(%{"type" => "string", "value" => value}) when is_binary(value), do: value

  defp decode_key!(key) do
    raise ArgumentError, "invalid auth secret envelope key #{inspect(key)}"
  end
end
