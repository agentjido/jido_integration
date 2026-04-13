# `Jido.Integration.V2.ControlPlane.ArtifactStore`

Durable artifact-reference truth owned by `control_plane`.

# `fetch_artifact_ref`

```elixir
@callback fetch_artifact_ref(String.t()) ::
  {:ok, Jido.Integration.V2.ArtifactRef.t()} | :error
```

# `list_artifact_refs`

```elixir
@callback list_artifact_refs(String.t()) :: [Jido.Integration.V2.ArtifactRef.t()]
```

# `put_artifact_ref`

```elixir
@callback put_artifact_ref(Jido.Integration.V2.ArtifactRef.t()) :: :ok | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
