# Developer Index

This section is for contributors who need the internal map of the repo rather
than the public operating model.

## What To Read First

1. read [Core Packages](core_packages.md) for the package-by-package map
2. read [Request Lifecycle](request_lifecycle.md) to understand the end-to-end
   flow
3. read [State And Verification](state_and_verification.md) to understand how
   the repo is tested, documented, and validated

## Scope

This section covers:

- the core package topology
- how data and execution move through the system
- what owns state, replay, and durability
- how to verify changes locally
- where to place new code so the boundaries stay clean

Use the other root guides for the external model. Use this section when you are
changing the internals.

## Related Guides

- [Architecture](../architecture.md)
- [Runtime Model](../runtime_model.md)
- [Durability](../durability.md)
- [Conformance](../conformance.md)
