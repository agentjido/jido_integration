# `Jido.Integration.V2.EvidenceRef`

Stable reference to a source record backing a packet, decision, or interpretation.

# `kind`

```elixir
@type kind() ::
  :run
  | :attempt
  | :event
  | :artifact
  | :trigger
  | :target
  | :connection
  | :install
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.EvidenceRef{
  id: binary(),
  kind:
    (:run
     | :attempt
     | :event
     | :artifact
     | :trigger
     | :target
     | :connection
     | :install)
    | binary(),
  metadata: map(),
  packet_ref: binary(),
  ref: nil | nil | binary(),
  subject: any()
}
```

# `dump`

```elixir
@spec dump(t()) :: %{
  ref: String.t(),
  kind: kind(),
  id: String.t(),
  packet_ref: String.t(),
  subject: map(),
  metadata: map()
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
