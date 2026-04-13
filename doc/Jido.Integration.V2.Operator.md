# `Jido.Integration.V2.Operator`

Shared read-only operator surface over durable auth and control-plane truth.

This module packages durable discovery, compatibility, and review state
without introducing a second store or cache.

# `capability_summary`

```elixir
@type capability_summary() :: %{
  capability_id: String.t(),
  connector_id: String.t(),
  runtime_class: atom(),
  kind: atom(),
  transport_profile: atom(),
  name: String.t(),
  display_name: String.t(),
  description: String.t(),
  required_scopes: [String.t()],
  runtime: map(),
  consumer_surface: map()
}
```

# `compatible_target_match`

```elixir
@type compatible_target_match() :: %{
  target: Jido.Integration.V2.TargetDescriptor.t(),
  negotiated_versions: map(),
  capability: capability_summary(),
  connector: connector_summary()
}
```

# `connector_summary`

```elixir
@type connector_summary() :: %{
  connector_id: String.t(),
  display_name: String.t(),
  description: String.t(),
  category: String.t(),
  tags: [String.t()],
  maturity: atom(),
  publication: atom(),
  auth_type: atom(),
  runtime_families: [atom()],
  capability_ids: [String.t()],
  capabilities: [capability_summary()]
}
```

# `projected_connector_summary`

```elixir
@type projected_connector_summary() :: %{
  connector_id: String.t(),
  display_name: String.t(),
  description: String.t(),
  category: String.t(),
  tags: [String.t()],
  docs_refs: [String.t()],
  maturity: atom(),
  publication: atom(),
  generated_plugin: %{module: module(), name: String.t(), state_key: atom()},
  generated_action_names: [String.t()],
  generated_sensor_names: [String.t()],
  common_projected_operations: [map()],
  common_projected_triggers: [map()]
}
```

# `review_packet`

```elixir
@type review_packet() :: %{
  metadata: Jido.Integration.V2.ReviewProjection.dump_t(),
  run: Jido.Integration.V2.Run.t(),
  attempt: Jido.Integration.V2.Attempt.t() | nil,
  attempts: [Jido.Integration.V2.Attempt.t()],
  events: [Jido.Integration.V2.Event.t()],
  artifacts: [Jido.Integration.V2.ArtifactRef.t()],
  triggers: [Jido.Integration.V2.TriggerRecord.t()],
  target: Jido.Integration.V2.TargetDescriptor.t() | nil,
  connection: Jido.Integration.V2.Auth.Connection.t() | nil,
  install: Jido.Integration.V2.Auth.Install.t() | nil,
  capability: capability_summary(),
  connector: connector_summary()
}
```

# `catalog_entries`

```elixir
@spec catalog_entries() :: [connector_summary()]
```

# `compatible_targets_for`

```elixir
@spec compatible_targets_for(String.t(), map()) ::
  {:ok, [compatible_target_match()]}
  | {:error, :unknown_capability | :unknown_connector}
```

# `projected_catalog_entries`

```elixir
@spec projected_catalog_entries() :: [projected_connector_summary()]
```

# `review_packet`

```elixir
@spec review_packet(String.t(), map()) ::
  {:ok, review_packet()}
  | {:error,
     :unknown_run | :unknown_attempt | :unknown_capability | :unknown_connector}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
