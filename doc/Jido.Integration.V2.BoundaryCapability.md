# `Jido.Integration.V2.BoundaryCapability`

Typed boundary capability advertisement for target descriptors.

`TargetDescriptor.extensions["boundary"]` is the authored baseline contract
for boundary capability advertisement. Runtimes may merge worker-local facts
into that baseline at execution time to build a runtime-merged live
capability view, but those live facts must sharpen the authored baseline
rather than silently widen it.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.BoundaryCapability{
  attach_modes: [binary()],
  boundary_classes: [binary()],
  checkpointing: boolean(),
  supported: boolean()
}
```

# `merge`

```elixir
@spec merge(t() | map() | keyword() | nil, t() | map() | keyword() | nil) :: t() | nil
```

Merges worker-local facts into an authored baseline advertisement.

Merge semantics are intentionally restrictive:

- boolean support and checkpointing flags may tighten from `true` to `false`
- boundary class and attach mode lists may narrow through intersection
- live facts do not widen the authored baseline silently

# `new`

```elixir
@spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
```

Builds a boundary capability advertisement from validated attributes.

# `new!`

```elixir
@spec new!(map() | keyword() | t()) :: t()
```

Builds a boundary capability advertisement or raises on validation failure.

# `schema`

```elixir
@spec schema() :: Zoi.schema()
```

Returns the Zoi schema for boundary capability advertisements.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
