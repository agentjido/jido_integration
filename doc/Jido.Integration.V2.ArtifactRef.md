# `Jido.Integration.V2.ArtifactRef`

Stable public reference to a run artifact.

Artifacts are references by default. The contract stores integrity metadata,
a resolvable `payload_ref`, and retention/redaction posture without carrying
the artifact body inline.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.ArtifactRef{
  artifact_id: binary(),
  artifact_type:
    (:event_log
     | :stdout
     | :stderr
     | :diff
     | :tarball
     | :tool_output
     | :log
     | :custom)
    | binary(),
  attempt_id: binary(),
  checksum: binary(),
  metadata: map(),
  payload_ref: any(),
  redaction_status: (:clear | :redacted | :withheld) | binary(),
  retention_class: any(),
  run_id: binary(),
  size_bytes: integer(),
  transport_mode: (:inline | :chunked | :object_store) | binary()
}
```

# `new`

```elixir
@spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
```

# `new!`

```elixir
@spec new!(map() | keyword() | t()) :: t()
```

# `schema`

```elixir
@spec schema() :: Zoi.schema()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
