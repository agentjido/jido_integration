# `Jido.Integration.V2.CanonicalJson`

Spine-owned canonical JSON normalization and RFC 8785 / JCS encoding helpers.

# `scalar`

```elixir
@type scalar() :: nil | boolean() | integer() | float() | String.t()
```

JSON-safe scalar value after normalization

# `value`

```elixir
@type value() :: scalar() | [value()] | %{required(String.t()) =&gt; value()}
```

Normalized JSON value with string-keyed objects only

# `checksum!`

```elixir
@spec checksum!(term()) :: Jido.Integration.V2.Contracts.checksum()
```

# `encode`

```elixir
@spec encode(term()) :: {:ok, String.t()} | {:error, Exception.t()}
```

# `encode!`

```elixir
@spec encode!(term()) :: String.t()
```

# `normalize`

```elixir
@spec normalize(term()) :: {:ok, value()} | {:error, Exception.t()}
```

# `normalize!`

```elixir
@spec normalize!(term()) :: value()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
