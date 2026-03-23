# Jido Integration V2 Runtime ASM Bridge

Integration-owned `Jido.Harness.RuntimeDriver` from
`/home/home/p/g/n/jido_harness` for the authored `asm` driver, backed by
`/home/home/p/g/n/agent_session_manager` and the
`/home/home/p/g/n/cli_subprocess_core` lane beneath it.

This package is the permanent home for the external ASM-to-Harness projection.
It keeps ASM's pid-based session references inside a private store keyed by
`session_id`, so public Session Control handles stay stable and transport-safe
while `jido_integration` itself stays at the Harness seam.

Current responsibilities:

- publish the `asm` Harness runtime driver used by the control plane
- normalize ASM events and results into Harness Session Control IR structs
- preserve external-runtime session reuse without leaking kernel-private refs
- localize the `/home/home/p/g/n/agent_session_manager` dependency so
  connector packages can keep their shared dependency surface at
  `/home/home/p/g/n/jido_harness`

This package does not own control-plane truth, provider SDK logic, or durable
artifact policy. It only projects ASM into the shared Harness contract above
`/home/home/p/g/n/cli_subprocess_core`.
