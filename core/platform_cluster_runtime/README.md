# Platform Cluster Runtime

Canonical Horde runtime package for Phase 7 memory-path singleton placement.

`Platform.Cluster.Runtime` owns the distributed registry/supervisor setup for
multi-node memory substrate work. Memory-path packages use this package instead
of constructing Horde locally or using `:global`.
