#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
require_command curl
sudo systemctl is-active --quiet k3s || fail "k3s is not active. Run 00-install-k3s.sh first."

wait_for_node

info "Creating project namespaces"
kctl apply -f "$REPO_ROOT/platform/namespaces/namespaces.yaml"

info "Deploying the foundation test application"
kctl apply -f "$REPO_ROOT/platform/k3s/test-workload.yaml"

info "Waiting for the foundation deployment"
kctl -n demo rollout status deployment/foundation-test --timeout=180s

info "Testing ingress through its required Host header"
HTTP_CODE="$(curl -sS -o /tmp/softcon-foundation-response.html -w '%{http_code}'   -H 'Host: aiops-demo.local' http://127.0.0.1)"

[[ "$HTTP_CODE" == "200" ]] ||
  fail "Foundation ingress returned HTTP $HTTP_CODE instead of 200"

info "Foundation resources"
kctl -n demo get deployment,pods,service,ingress -o wide

info "Stage 1 complete: foundation ingress returned HTTP 200"
