defmodule Jido.Integration.ModelInvocation.Canonical do
  @moduledoc false

  alias Jido.Integration.V2.CanonicalJson

  @spec checksum!(term()) :: String.t()
  def checksum!(value), do: CanonicalJson.checksum!(value)

  @spec artifact_ref(String.t(), term()) :: String.t()
  def artifact_ref(prefix, value) when is_binary(prefix) do
    digest =
      value
      |> checksum!()
      |> String.replace_prefix("sha256:", "")

    "#{prefix}/sha256:#{digest}"
  end
end
