#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

info() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

require_repo_root() {
  [[ -f "$REPO_ROOT/platform/namespaces/namespaces.yaml" ]] ||
    fail "Repository layout not found. Run this script from the cloned softcon-2027 repository."
}

kctl() {
  sudo k3s kubectl "$@"
}

wait_for_node() {
  info "Waiting for the Kubernetes node to become Ready"
  kctl wait --for=condition=Ready node --all --timeout=180s
}
