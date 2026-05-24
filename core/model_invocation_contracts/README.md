# Jido Model Invocation Contracts

This package owns the stable ref-only DTOs used when Mezzanine asks Jido
Integration to invoke a model.

It does not execute providers. It validates and dumps:

- `Jido.Integration.ModelInvocation.Request`
- `Jido.Integration.ModelInvocation.Receipt`
- `Jido.Integration.ModelInvocation.StreamFragment`

The DTOs carry context packet refs, route decision refs, prompt and provider
payload artifact refs, credential lease refs, token/cost summaries, and trace
refs. They deliberately reject raw prompts, raw message lists, provider payload
bodies, credentials, and auth headers.

Execution lives in `core/inference_runtime` or the existing control-plane
inference path.
