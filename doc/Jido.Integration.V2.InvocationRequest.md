# `Jido.Integration.V2.InvocationRequest`

Typed public request for capability invocation through the v2 facade.

The request keeps the stable control-plane invoke fields explicit while still
allowing non-reserved extension opts to flow through to runtime context.

When a capability requires auth, the public binding is `connection_id`.
Credential refs remain internal auth and execution plumbing.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.InvocationRequest{
  actor_id: nil | nil | binary(),
  aggregator_epoch: nil | nil | any(),
  aggregator_id: nil | nil | binary(),
  allowed_operations: nil | nil | [binary()],
  capability_id: binary(),
  connection_id: nil | nil | binary(),
  environment: nil | nil | atom() | binary(),
  extensions: any(),
  input: any(),
  sandbox: any(),
  target_id: nil | nil | binary(),
  tenant_id: nil | nil | binary(),
  trace_id: nil | nil | binary()
}
```

# `new`

```elixir
@spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
```

# `new!`

```elixir
@spec new!(t() | map() | keyword()) :: t()
```

# `schema`

```elixir
@spec schema() :: Zoi.schema()
```

# `to_opts`

```elixir
@spec to_opts(t()) :: keyword()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
