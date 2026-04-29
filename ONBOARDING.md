# jido_integration Onboarding

Read `AGENTS.md` first; the managed gn-ten section is the repo contract.
`CLAUDE.md` must stay a one-line compatibility shim containing `@AGENTS.md`.

## Owns

Connector gateway contracts, credential leases, capability registry/runtime
control, lower invocation, and provider-free connector conformance.

## Does Not Own

Semantic reasoning, product UX, Citadel authority, Mezzanine audit truth, or
ExecutionPlane lane implementation.

## First Task

```bash
cd /home/home/p/g/n/jido_integration
mix ci
cd /home/home/p/g/n/stack_lab
mix gn_ten.plan --repo jido_integration
```

## Proofs

StackLab owns assembled proof. Use `/home/home/p/g/n/stack_lab/proof_matrix.yml`
and `/home/home/p/g/n/stack_lab/docs/gn_ten_proof_matrix.md`.

## Common Changes

Never expose raw secrets or provider payloads in public DTOs or receipts. For
connector work, keep fixture/provider-free tests green before live smoke exists.
For shared adapter work, preserve shared-library defaults/options/tool policy at
the Jido boundary and prove it with package-local tests plus root `mix ci`.
