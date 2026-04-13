# `Jido.Integration.V2.TargetDescriptor`

Stable public descriptor for an execution target.

A target is an execution environment advertisement, not a connector
identity. Compatibility is explicit through runtime class, target
capability, semantic versioning, and protocol version negotiation.

Authored connector/runtime posture stays primary. Build compatibility
requirements from the authored capability contract and treat target
descriptors as compatibility plus location advertisements only. Targets do
not override authored runtime driver, provider, or options.

`extensions["boundary"]` is reserved for the authored baseline boundary
capability advertisement. Callers may combine that durable baseline with
worker-local runtime facts through `live_boundary_capability/2` to build a
runtime-merged live capability view when the lower-boundary result becomes
more specific at execution time.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.TargetDescriptor{
  capability_id: binary(),
  constraints: map(),
  extensions: map(),
  features: map(),
  health: (:healthy | :degraded | :unavailable) | binary(),
  location: map(),
  runtime_class: (:direct | :session | :stream) | binary(),
  target_id: binary(),
  version: binary()
}
```

# `authored_boundary_capability`

```elixir
@spec authored_boundary_capability(t()) ::
  Jido.Integration.V2.BoundaryCapability.t() | nil
```

Returns the authored baseline boundary capability advertisement, if present.

# `authored_requirements`

```elixir
@spec authored_requirements(Jido.Integration.V2.Capability.t(), map()) :: map()
```

Builds target compatibility requirements from authored capability truth.

Callers may add version or protocol preferences, but authored capability id,
runtime class, and any non-direct runtime-driver requirement remain primary.

# `compatibility`

```elixir
@spec compatibility(t(), map()) ::
  {:ok,
   %{runspec_version: String.t() | nil, event_schema_version: String.t() | nil}}
  | {:error, atom()}
```

# `live_boundary_capability`

```elixir
@spec live_boundary_capability(
  t(),
  map() | keyword() | Jido.Integration.V2.BoundaryCapability.t() | nil
) :: Jido.Integration.V2.BoundaryCapability.t() | nil
```

Returns a runtime-merged live boundary capability view for this target.

Worker-local facts may sharpen the authored baseline but do not widen it
silently. When no authored baseline is present, live facts normalize
directly.

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
