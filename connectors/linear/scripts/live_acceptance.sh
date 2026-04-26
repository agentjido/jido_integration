#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-all}"

if [[ $# -gt 0 ]]; then
  shift
fi

case "$mode" in
  auth|read|write|all)
    ;;
  *)
    echo "usage: scripts/live_acceptance.sh [auth|read|write|all] [options]" >&2
    exit 2
    ;;
esac

cd "$package_dir"

case "$mode" in
  auth)
    mix run examples/linear_auth_lifecycle.exs "$@"
    ;;
  read)
    mix run examples/linear_live_read_acceptance.exs "$@"
    ;;
  write)
    mix run examples/linear_live_write_acceptance.exs "$@"
    ;;
  all)
    mix run examples/linear_live_all_acceptance.exs "$@"
    ;;
esac
