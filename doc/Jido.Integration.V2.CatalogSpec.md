# `Jido.Integration.V2.CatalogSpec`

Authored catalog metadata for a connector manifest.

# `maturity`

```elixir
@type maturity() :: :experimental | :alpha | :beta | :ga
```

# `publication`

```elixir
@type publication() :: :internal | :public | :private
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.CatalogSpec{
  category: binary(),
  description: binary(),
  display_name: binary(),
  docs_refs: [binary()],
  maturity: (:experimental | :alpha | :beta | :ga) | binary(),
  metadata: map(),
  publication: (:internal | :public | :private) | binary(),
  tags: [binary()]
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
