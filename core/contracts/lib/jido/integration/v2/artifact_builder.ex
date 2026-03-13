defmodule Jido.Integration.V2.ArtifactBuilder do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Contracts

  @default_ttl_seconds 3_600

  @spec build!(keyword()) :: ArtifactRef.t()
  def build!(opts) when is_list(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    attempt_id = Keyword.fetch!(opts, :attempt_id)
    artifact_type = Keyword.fetch!(opts, :artifact_type)
    key = Keyword.fetch!(opts, :key)
    content = Keyword.fetch!(opts, :content)

    encoded = encode(content)
    checksum = checksum(encoded)
    size_bytes = byte_size(encoded)

    ArtifactRef.new!(%{
      artifact_id: Keyword.get(opts, :artifact_id, Contracts.next_id("artifact")),
      run_id: run_id,
      attempt_id: attempt_id,
      artifact_type: artifact_type,
      transport_mode: Keyword.get(opts, :transport_mode, :object_store),
      checksum: checksum,
      size_bytes: size_bytes,
      payload_ref: %{
        store: Keyword.get(opts, :store, "connector_review"),
        key: key,
        ttl_s: Keyword.get(opts, :ttl_s, @default_ttl_seconds),
        access_control: Keyword.get(opts, :access_control, :run_scoped),
        checksum: checksum,
        size_bytes: size_bytes
      },
      retention_class: Keyword.get(opts, :retention_class, "connector_review"),
      redaction_status: Keyword.get(opts, :redaction_status, :clear),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  @spec digest(term()) :: Contracts.checksum()
  def digest(value) do
    value
    |> encode()
    |> checksum()
  end

  defp encode(value) when is_binary(value), do: value
  defp encode(value), do: :erlang.term_to_binary(value)

  defp checksum(encoded) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, encoded), case: :lower)
  end
end
