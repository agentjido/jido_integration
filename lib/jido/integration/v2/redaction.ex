defmodule Jido.Integration.V2.Redaction do
  @moduledoc """
  Recursive redaction for audit-visible durable truth.
  """

  @redacted "[REDACTED]"
  @non_sensitive_keys [
    "cachecreationinputtokens",
    "cachereadinputtokens",
    "completiontokens",
    "inputtokens",
    "outputtokens",
    "prompttokens",
    "reasoningtokens",
    "totaltokens"
  ]
  @sensitive_fragments [
    "accesskey",
    "accesstoken",
    "apikey",
    "authorization",
    "bearer",
    "clientsecret",
    "credential",
    "grant",
    "password",
    "privatekey",
    "refreshtoken",
    "secret",
    "sessiontoken",
    "signingkey",
    "token"
  ]

  @spec redact(term()) :: term()
  def redact(value), do: do_redact(value)

  @spec redacted() :: String.t()
  def redacted, do: @redacted

  defp do_redact(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> do_redact()
  end

  defp do_redact(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      sanitized =
        if sensitive_key?(key) do
          @redacted
        else
          do_redact(value)
        end

      Map.put(acc, key, sanitized)
    end)
  end

  defp do_redact(list) when is_list(list), do: Enum.map(list, &do_redact/1)

  defp do_redact(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&do_redact/1)
    |> List.to_tuple()
  end

  defp do_redact(value), do: value

  defp sensitive_key?(key) when is_atom(key), do: sensitive_key?(Atom.to_string(key))

  defp sensitive_key?(key) when is_binary(key) do
    normalized =
      key
      |> String.downcase()
      |> String.to_charlist()
      |> Enum.filter(&lowercase_alphanumeric?/1)
      |> List.to_string()

    normalized not in @non_sensitive_keys and
      Enum.any?(@sensitive_fragments, &String.contains?(normalized, &1))
  end

  defp sensitive_key?(_key), do: false

  defp lowercase_alphanumeric?(character) when character in ?a..?z, do: true
  defp lowercase_alphanumeric?(character) when character in ?0..?9, do: true
  defp lowercase_alphanumeric?(_character), do: false
end
