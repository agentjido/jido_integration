# Jido Integration V2 Runtime ASM Bridge

Integration-owned `Jido.Harness.RuntimeDriver` backed by `agent_session_manager`.

This package is the permanent home for the external ASM-to-Harness projection.
It keeps ASM's pid-based session references inside a private store keyed by
`session_id`, so public Session Control handles stay stable and transport-safe.

Current responsibilities:

- publish the ASM-backed Harness runtime driver used by the control plane
- normalize ASM events and results into Harness Session Control IR structs
- preserve external-runtime session reuse without leaking kernel-private refs

This package does not own control-plane truth, provider SDK logic, or durable
artifact policy. It only projects ASM into the shared Harness contract.
