#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="${1:-all}"
if [[ $# -gt 0 ]]; then
  shift
fi

cd "${PACKAGE_DIR}"

case "${MODE}" in
  auth)
    mix run examples/github_auth_lifecycle.exs "$@"
    ;;
  read)
    mix run examples/github_live_read_acceptance.exs "$@"
    ;;
  write)
    mix run examples/github_live_write_acceptance.exs "$@"
    ;;
  all)
    mix run examples/github_live_all_acceptance.exs "$@"
    ;;
  *)
    cat <<'USAGE'
usage: scripts/live_acceptance.sh [auth|read|write|all] [options]

Runs the package-local GitHub live proofs through the current v2 auth and platform surface.

Examples:
  scripts/live_acceptance.sh auth
  scripts/live_acceptance.sh read --repo owner/repo
  scripts/live_acceptance.sh write --write-repo owner/sandbox-repo
  scripts/live_acceptance.sh all --repo owner/repo --write-repo owner/sandbox-repo
USAGE
    exit 1
    ;;
esac
