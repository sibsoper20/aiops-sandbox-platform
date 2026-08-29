#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
sudo systemctl is-active --quiet k3s || fail "k3s is not active"

kctl -n demo get statefulset demo-postgres >/dev/null 2>&1 ||
  fail "PostgreSQL is not deployed. Complete scripts/20-deploy-demo-application.sh first."

info "Deploying the incident-capable API with incident controls disabled"
kctl apply -f "$REPO_ROOT/apps/demo-api/kubernetes/api.yaml"
kctl -n demo rollout status deployment/demo-api --timeout=300s

info "Confirming the immutable container image"
IMAGE="$(kctl -n demo get deployment demo-api -o jsonpath='{.spec.template.spec.containers[0].image}')"
[[ "$IMAGE" == *":sha-1bd638d" ]] || fail "Unexpected API image: $IMAGE"

info "Confirming the healthy baseline"
kctl -n demo run demo-api-baseline-check --rm -i --restart=Never \
  --image=busybox:1.37.0 --quiet -- \
  /bin/sh -ec 'for attempt in $(seq 1 30); do
    if wget -qO- http://demo-api.demo.svc.cluster.local:8080/readyz; then
      exit 0
    fi
    sleep 2
  done
  echo "Demo API did not become reachable" >&2
  exit 1'

info "Stage 24 complete"
