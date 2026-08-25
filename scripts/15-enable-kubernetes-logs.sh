#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
sudo systemctl is-active --quiet k3s || fail "k3s is not active"

kctl -n observability get statefulset loki >/dev/null 2>&1 ||
  fail "Loki is not deployed. Complete scripts/13-deploy-loki.sh first."
kctl -n observability get deployment alloy >/dev/null 2>&1 ||
  fail "Alloy is not deployed. Complete scripts/09-deploy-alloy.sh first."

info "Applying the minimum RBAC required for Kubernetes pod logs"
kctl apply -f "$REPO_ROOT/observability/alloy/log-rbac.yaml"

info "Checking Alloy log permissions"
kctl auth can-i list pods \
  --as=system:serviceaccount:observability:alloy
kctl auth can-i get pods/log \
  --as=system:serviceaccount:observability:alloy

info "Updating the Alloy configuration"
kctl -n observability create configmap alloy-config \
  --from-file=config.alloy="$REPO_ROOT/observability/alloy/config.alloy" \
  --dry-run=client -o yaml | kctl apply -f -

info "Restarting Alloy so the log pipeline is loaded deterministically"
kctl -n observability rollout restart deployment/alloy
kctl -n observability rollout status deployment/alloy --timeout=300s

info "Checking the loaded Alloy configuration"
sleep 5
ALLOY_LOGS="$(kctl -n observability logs deployment/alloy -c alloy --tail=100)"
printf '%s\n' "$ALLOY_LOGS"

if grep -Eiq 'level=error|failed to evaluate|configuration.*error' <<<"$ALLOY_LOGS"; then
  fail "Alloy reported a configuration or runtime error"
fi

info "Stage 15 complete"
