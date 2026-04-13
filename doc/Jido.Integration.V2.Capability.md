# `Jido.Integration.V2.Capability`

Derived executable projection used by the control plane.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Capability{
  connector: binary(),
  handler: atom(),
  id: binary(),
  kind: atom() | binary(),
  metadata: map(),
  runtime_class: (:direct | :session | :stream) | binary(),
  transport_profile: atom() | binary()
}
```

# `from_operation!`

```elixir
@spec from_operation!(String.t(), Jido.Integration.V2.OperationSpec.t()) :: t()
```

# `from_trigger!`

```elixir
@spec from_trigger!(String.t(), Jido.Integration.V2.TriggerSpec.t()) :: t()
```

# `new`

```elixir
@spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
```

# `new!`

```elixir
@spec new!(map() | keyword() | t()) :: t()
```

# `required_scopes`

```elixir
@spec required_scopes(t()) :: [String.t()]
```

# `schema`

```elixir
@spec schema() :: Zoi.schema()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
