#!/usr/bin/env bash
set -euo pipefail

mode="${1:-read}"

case "$mode" in
  read)
    export JIDO_INTEGRATION_GITHUB_LIVE=1
    mix test test/examples/github_auth_lifecycle_test.exs
    mix test test/examples/github_integration_test.exs
    ;;
  write)
    : "${GITHUB_TEST_OWNER:?set GITHUB_TEST_OWNER}"
    : "${GITHUB_TEST_REPO:?set GITHUB_TEST_REPO}"
    export JIDO_INTEGRATION_GITHUB_LIVE=1
    export JIDO_INTEGRATION_GITHUB_LIVE_WRITE=1
    mix test test/examples/github_integration_test.exs
    ;;
  *)
    echo "usage: scripts/live_acceptance.sh [read|write]" >&2
    exit 1
    ;;
esac
