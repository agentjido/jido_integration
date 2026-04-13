# `Jido.Integration.V2.SubjectRef`

Stable reference to the primary node-local subject a higher-order record is about.

# `kind`

```elixir
@type kind() ::
  :run
  | :attempt
  | :event
  | :artifact
  | :trigger
  | :capability
  | :target
  | :connection
  | :install
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.SubjectRef{
  id: binary(),
  kind:
    (:run
     | :attempt
     | :event
     | :artifact
     | :trigger
     | :capability
     | :target
     | :connection
     | :install)
    | binary(),
  metadata: map(),
  ref: nil | nil | binary()
}
```

# `dump`

```elixir
@spec dump(t()) :: %{ref: String.t(), kind: kind(), id: String.t(), metadata: map()}
```

# `new`

```elixir
@spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
```

# `new!`

```elixir
@spec new!(map() | keyword() | t()) :: t()
```

# `ref`

```elixir
@spec ref(kind(), String.t()) :: String.t()
```

# `schema`

```elixir
@spec schema() :: Zoi.schema()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
