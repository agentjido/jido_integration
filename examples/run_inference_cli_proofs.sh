#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
export SSLKEYLOGFILE="${SSLKEYLOGFILE:-/tmp/jido_integration_sslkey.log}"
export MIX_OS_CONCURRENCY_LOCK="${MIX_OS_CONCURRENCY_LOCK:-0}"

echo "==> core/control_plane CLI endpoint proof"
(
  cd "$repo_root/core/control_plane"
  mix run examples/inference_cli_endpoint_baseline.exs
)

echo "==> apps/inference_ops full proof"
(
  cd "$repo_root/apps/inference_ops"
  mix run examples/inference_proof.exs
)
