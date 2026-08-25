#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
sudo -v

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/softcon-aiops-demo-application-$TIMESTAMP.log"
PRODUCT="Persistent SOFTCON Order $TIMESTAMP"

kctl -n demo rollout status statefulset/demo-postgres --timeout=180s
kctl -n demo rollout status deployment/demo-api --timeout=180s

request_api() {
  curl -fsS -H 'Host: orders.aiops.local' "$@"
}

info "Waiting for application ingress"
for _ in {1..30}; do
  request_api http://127.0.0.1/readyz >/tmp/softcon-demo-ready.json 2>/dev/null && break
  sleep 2
done

HEALTH="$(request_api http://127.0.0.1/healthz)"
READY="$(request_api http://127.0.0.1/readyz)"
CREATED="$(request_api -X POST \
  -H 'Content-Type: application/json' \
  --data "{\"product\":\"$PRODUCT\",\"quantity\":3}" \
  http://127.0.0.1/api/orders)"
ORDER_ID="$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' <<<"$CREATED")"

[[ -n "$ORDER_ID" ]] || fail "Created order ID was not returned"
grep -q '"storage":"postgres"' <<<"$READY" || fail "API is not using PostgreSQL"

METRICS="$(request_api http://127.0.0.1/metrics)"
grep -q 'demo_orders_created_total' <<<"$METRICS" || fail "Application metrics were not returned"
grep -q 'demo_db_queries_total' <<<"$METRICS" || fail "Database metrics were not returned"

info "Restarting PostgreSQL to prove persistent storage"
kctl -n demo rollout restart statefulset/demo-postgres
kctl -n demo rollout status statefulset/demo-postgres --timeout=300s

info "Waiting for API readiness after the database restart"
for _ in {1..60}; do
  if request_api http://127.0.0.1/readyz >/tmp/softcon-demo-ready-after-restart.json 2>/dev/null; then
    break
  fi
  sleep 2
done

ORDERS="$(request_api 'http://127.0.0.1/api/orders?limit=100')"
grep -q "$ORDER_ID" <<<"$ORDERS" || fail "Created order did not survive the PostgreSQL restart"

PVC_STATUS="$(kctl -n demo get pvc data-demo-postgres-0 -o jsonpath='{.status.phase}')"
[[ "$PVC_STATUS" == "Bound" ]] || fail "PostgreSQL PVC is not Bound"

{
  info "Application resources"
  kctl -n demo get statefulset,deployment,pods,service,ingress,pvc \
    -l app.kubernetes.io/part-of=softcon-aiops-demo -o wide

  info "Health"
  printf '%s\n' "$HEALTH"

  info "Readiness before restart"
  printf '%s\n' "$READY"

  info "Created order"
  printf '%s\n' "$CREATED"

  info "Readiness after PostgreSQL restart"
  cat /tmp/softcon-demo-ready-after-restart.json

  info "Persistent order lookup"
  printf '%s\n' "$ORDERS"

  info "PostgreSQL volume"
  printf 'PVC data-demo-postgres-0: %s\n' "$PVC_STATUS"

  info "Application metrics"
  printf '%s\n' "$METRICS"

  info "Recent structured logs"
  kctl -n demo logs deployment/demo-api --tail=20

  info "Verification passed"
  printf 'Report: %s\n' "$REPORT"
} | tee "$REPORT"
