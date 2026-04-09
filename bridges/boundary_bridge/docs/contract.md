# Contract Overview

`Jido.BoundaryBridge` owns the lower-boundary contract between authored runtime
intent and sandbox-kernel lifecycle.

The package ships:

- `Jido.BoundaryBridge.AllocateBoundaryRequest`
- `Jido.BoundaryBridge.ReopenBoundaryRequest`
- `Jido.BoundaryBridge.BoundarySessionDescriptor`
- explicit projection helpers for attach grants and durable boundary metadata
- typed extension accessors such as `Jido.BoundaryBridge.Extensions.Tracing`
- pure request translation and descriptor normalization helpers
- one package-local Splode error module for bridge-facing failures

The bridge remains kernel-neutral:

- descriptors may use `attach.mode == :not_applicable`
- attach readiness is meaningful only for `:attachable` descriptors
- startup TTL hints stay in the allocate request instead of leaking BEAM-local
  crash-tracking fields into the public contract
- route, replay, approval, callback, and identity carriage stay explicit in
  named bridge-facing fields rather than becoming transport-specific metadata
