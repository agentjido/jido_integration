# Jido Inference Operation Policy

Owner phase: Adaptive Phase 3.

This package binds governed model operation classes to model profile refs,
authority refs, tenant refs, capability requirements, and budget refs. It is
the policy-side contract used before GEPA, TRINITY, embeddings, rerank,
summarization, reflection, or tool-call operations materialize model calls.

The package is regex-free and does not read ambient environment configuration.
