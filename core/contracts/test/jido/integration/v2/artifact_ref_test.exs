defmodule Jido.Integration.V2.ArtifactRefTest do
  use ExUnit.Case

  alias Jido.Integration.V2.ArtifactRef

  test "keeps explicit integrity metadata and folds unknown fields into metadata" do
    checksum = "sha256:" <> String.duplicate("a", 64)

    artifact_ref =
      ArtifactRef.new!(%{
        artifact_id: "artifact-42",
        run_id: "run-42",
        attempt_id: "run-42:1",
        artifact_type: :stdout,
        transport_mode: :object_store,
        checksum: checksum,
        size_bytes: 512,
        payload_ref: %{
          store: "s3",
          key: "sha256:" <> String.duplicate("b", 64),
          ttl_s: 86_400,
          access_control: :run_scoped,
          checksum: checksum,
          size_bytes: 512
        },
        retention_class: "stdout_stderr",
        redaction_status: :redacted,
        metadata: %{content_encoding: "gzip"},
        trace_id: "trace-42"
      })

    assert artifact_ref.artifact_id == "artifact-42"
    assert artifact_ref.payload_ref.access_control == :run_scoped
    assert artifact_ref.metadata.content_encoding == "gzip"
    assert artifact_ref.metadata.trace_id == "trace-42"
  end

  test "rejects payload references that fail integrity or locality rules" do
    checksum = "sha256:" <> String.duplicate("c", 64)

    assert_raise ArgumentError, ~r/checksum/, fn ->
      ArtifactRef.new!(%{
        artifact_id: "artifact-bad-checksum",
        run_id: "run-1",
        attempt_id: "run-1:1",
        artifact_type: :tool_output,
        transport_mode: :object_store,
        checksum: checksum,
        size_bytes: 128,
        payload_ref: %{
          store: "s3",
          key: "sha256:" <> String.duplicate("d", 64),
          ttl_s: 3_600,
          access_control: :run_scoped,
          checksum: "sha256:" <> String.duplicate("e", 64),
          size_bytes: 128
        },
        retention_class: "tool_outputs",
        redaction_status: :clear
      })
    end

    assert_raise ArgumentError, ~r/local file/, fn ->
      ArtifactRef.new!(%{
        artifact_id: "artifact-local-path",
        run_id: "run-2",
        attempt_id: "run-2:1",
        artifact_type: :diff,
        transport_mode: :object_store,
        checksum: checksum,
        size_bytes: 128,
        payload_ref: %{
          store: "file",
          key: "/tmp/artifact.diff",
          ttl_s: 3_600,
          access_control: :run_scoped,
          checksum: checksum,
          size_bytes: 128
        },
        retention_class: "diffs_tarballs",
        redaction_status: :clear
      })
    end
  end
end
