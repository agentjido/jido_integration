#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="${1:-auth}"

cd "${PACKAGE_DIR}"
export MIX_ENV=dev

case "${MODE}" in
  auth)
    mix run examples/notion_auth_lifecycle.exs
    ;;
  read)
    mix run examples/notion_live_read_acceptance.exs
    ;;
  write)
    mix run examples/notion_live_write_acceptance.exs
    ;;
  *)
    cat <<'USAGE'
usage: scripts/live_acceptance.sh [auth|read|write]

Runs the package-local Notion live proofs through the current v2 auth and platform surface.
USAGE
    exit 1
    ;;
esac
