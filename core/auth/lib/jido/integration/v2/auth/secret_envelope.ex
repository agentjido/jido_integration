defmodule Jido.Integration.V2.Auth.SecretEnvelope do
  @moduledoc false

  @default_key_id "dev-local-1"
  @default_key Base.encode64(:crypto.hash(:sha256, "jido_integration_v2_auth_dev_key"))
  @cipher :aes_256_gcm
  @iv_bytes 12
  @aad_prefix "jido.integration.v2.auth"

  @spec encrypt(term(), String.t()) :: map()
  def encrypt(value, aad_suffix) do
    %{active_kid: kid, keys: keys} = keyring()
    key = key!(keys, kid)
    iv = :crypto.strong_rand_bytes(@iv_bytes)
    aad = aad(aad_suffix)
    plaintext = :erlang.term_to_binary(value)

    {ciphertext, tag} = :crypto.crypto_one_time_aead(@cipher, key, iv, plaintext, aad, true)

    %{
      "alg" => "A256GCM",
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
    :erlang.binary_to_term(plaintext)
  end

  @spec keyring() :: %{active_kid: String.t(), keys: map()}
  def keyring do
    Application.get_env(:jido_integration_v2_auth, :keyring, %{
      active_kid: @default_key_id,
      keys: %{@default_key_id => @default_key}
    })
  end

  defp aad(suffix), do: "#{@aad_prefix}:#{suffix}"

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
end
