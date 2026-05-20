# Jido Integration Code Smell Remediation

This guide records the repo-local implementation posture after the GN-TEN code
smell remediation pass.

## What Changed

- Auth and control-plane service objects are split into explicit lifecycle,
  registry, policy, persistence, replay, and invocation owners.
- Persistence resolution uses named runtime ownership instead of mutable
  `:persistent_term` state.
- GitHub fixtures are modularized so provider fixture data remains in
  connector/test zones.
- Atom alias parsing is bounded by owned vocabulary tables and negative tests.
- Connector/provider vocabulary is allowed in connector packages, manifests,
  fixtures, receipts, and trace data, but not as closed generic dispatch in
  platform core.

## Maintainer Rules

- Jido Integration owns connector/runtime invocation and lower facts.
- Higher repos should use bridge contracts rather than importing connector
  internals.
- Do not add unsafe atom creation, hidden persistence globals, or broad
  provider dispatch maps in generic core modules.

## QC

Use the repo root gate:

```bash
mix ci
```
