# Jido Integration V2 Stream Runtime

Owns pull-oriented stream execution for feed and protocol capabilities.

Current responsibilities:

- provider-managed stream lifecycle
- stream reuse keyed by capability-specific provider logic
- repeated pulls against a stable runtime reference
- canonical attempt events for stream start / reuse / completion / failure
