# `Jido.Integration.V2.Ingress`

Normalizes webhook and polling triggers into durable control-plane truth.

# `admission_result`

```elixir
@type admission_result() ::
  {:ok,
   %{
     status: :accepted | :duplicate,
     trigger: Jido.Integration.V2.TriggerRecord.t(),
     run: map()
   }}
  | {:error, %{reason: term(), trigger: Jido.Integration.V2.TriggerRecord.t()}}
```

# `admit_poll`

```elixir
@spec admit_poll(map(), Jido.Integration.V2.Ingress.Definition.t()) ::
  admission_result()
```

# `admit_webhook`

```elixir
@spec admit_webhook(map(), Jido.Integration.V2.Ingress.Definition.t()) ::
  admission_result()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
