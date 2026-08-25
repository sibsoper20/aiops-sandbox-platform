#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
sudo systemctl is-active --quiet k3s || fail "k3s is not active"

info "Creating or updating the Mimir configuration"
kctl -n observability create configmap mimir-config   --from-file=mimir.yaml="$REPO_ROOT/observability/mimir/mimir.yaml"   --dry-run=client -o yaml | kctl apply -f -

info "Deploying persistent single-process Mimir"
kctl apply -f "$REPO_ROOT/observability/mimir/manifest.yaml"

info "Waiting for the Mimir persistent volume"
for _ in {1..30}; do
  PVC_STATUS="$(kctl -n observability get pvc mimir-data -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "$PVC_STATUS" == "Bound" ]] && break
  sleep 2
done
[[ "${PVC_STATUS:-}" == "Bound" ]] || fail "Mimir PVC did not become Bound"

info "Waiting for Mimir"
kctl -n observability rollout status deployment/mimir --timeout=300s

info "Mimir resources"
kctl -n observability get deployment,pods,service,pvc   -l app.kubernetes.io/name=mimir -o wide

info "Stage 7 complete"
