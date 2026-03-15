# Jido Integration V2 Stream Runtime

Compatibility bridge for pull-oriented stream capabilities that still expose
the legacy provider contract.

Current responsibilities:

- publish a Harness runtime driver for legacy stream providers
- preserve stream reuse keyed by capability-specific provider logic
- keep `runtime_ref_id` and `session_id` durable at the control-plane boundary
- act as a temporary shim while permanent stream execution routes through Harness
