# `Jido.Integration.V2.RuntimeResult`

Shared runtime emission envelope for direct, session, and stream execution.

# `event_spec`

```elixir
@type event_spec() :: %{
  :type =&gt; String.t(),
  optional(:stream) =&gt; Jido.Integration.V2.Contracts.event_stream(),
  optional(:level) =&gt; Jido.Integration.V2.Contracts.event_level(),
  optional(:payload) =&gt; map(),
  optional(:payload_ref) =&gt; Jido.Integration.V2.Contracts.payload_ref(),
  optional(:trace) =&gt; Jido.Integration.V2.Contracts.trace_context(),
  optional(:target_id) =&gt; String.t(),
  optional(:session_id) =&gt; String.t(),
  optional(:runtime_ref_id) =&gt; String.t()
}
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.RuntimeResult{
  artifacts: [any()],
  events: [
    %{
      :type =&gt; binary(),
      :stream =&gt;
        (:assistant | :stdout | :stderr | :system | :control) | binary(),
      :level =&gt; (:debug | :info | :warn | :error) | binary(),
      :payload =&gt; any(),
      optional(:payload_ref) =&gt; nil | any(),
      :trace =&gt; any(),
      optional(:target_id) =&gt; nil | binary(),
      optional(:session_id) =&gt; nil | binary(),
      optional(:runtime_ref_id) =&gt; nil | binary()
    }
  ],
  output: nil | nil | any(),
  runtime_ref_id: nil | nil | binary()
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
