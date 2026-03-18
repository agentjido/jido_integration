# Jido Integration V2 Stream Runtime

Compatibility bridge for pull-oriented stream capabilities that still expose
the legacy provider contract.

Current responsibilities:

- publish a Harness runtime driver for legacy stream providers
- preserve stream reuse keyed by capability-specific provider logic
- keep `runtime_ref_id` and `session_id` durable at the control-plane boundary
- act as a temporary shim while permanent stream execution routes through Harness

This package is compatibility-only in Phase 0. The workspace scaffold no longer
generates new packages against this bridge.

New stream connectors should not treat this package as the final architecture.
Compose them manually against the real Harness target kernels (`asm` or
`jido_session`) instead of deepening this shim.
