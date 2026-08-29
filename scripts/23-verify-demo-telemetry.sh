#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
sudo -v

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/softcon-aiops-demo-telemetry-$TIMESTAMP.log"
GRAFANA_LOG="/tmp/softcon-demo-telemetry-grafana-$TIMESTAMP.log"
PF_PID=""

cleanup() {
  [[ -n "$PF_PID" ]] && kill "$PF_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

kctl -n demo rollout status deployment/demo-api --timeout=180s
kctl -n demo rollout status deployment/demo-traffic-generator --timeout=180s
kctl -n observability rollout status deployment/alloy --timeout=180s
kctl -n observability rollout status deployment/grafana --timeout=180s

info "Waiting for two Alloy scrape intervals"
sleep 35

ADMIN_USER="$(kctl -n observability get secret grafana-admin-credentials -o jsonpath='{.data.admin-user}' | base64 -d)"
ADMIN_PASSWORD="$(kctl -n observability get secret grafana-admin-credentials -o jsonpath='{.data.admin-password}' | base64 -d)"

kctl -n observability port-forward service/grafana 13000:80 >"$GRAFANA_LOG" 2>&1 &
PF_PID="$!"
for _ in {1..30}; do
  curl -fsS http://127.0.0.1:13000/api/health >/dev/null 2>&1 && break
  sleep 1
done

METRICS="$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASSWORD" --get \
  --data-urlencode 'query=demo_http_requests_total{job="demo-api"}' \
  http://127.0.0.1:13000/api/datasources/proxy/uid/mimir/api/v1/query)"
LOGS="$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASSWORD" --get \
  --data-urlencode 'query={namespace="demo",app="demo-api"}' \
  --data-urlencode 'limit=5' \
  http://127.0.0.1:13000/api/datasources/proxy/uid/loki/loki/api/v1/query_range)"
DASHBOARD="$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASSWORD" \
  'http://127.0.0.1:13000/api/search?query=SOFTCON%20Demo%20API')"

grep -q '"status":"success"' <<<"$METRICS" || fail "Mimir query failed"
grep -q 'demo_http_requests_total' <<<"$METRICS" || fail "Demo API metrics were not found in Mimir"
grep -q '"status":"success"' <<<"$LOGS" || fail "Loki query failed"
grep -q '"stream":' <<<"$LOGS" || fail "Demo API logs were not found in Loki"
grep -q '"uid":"softcon-demo-api"' <<<"$DASHBOARD" || fail "Demo API dashboard was not found"

{
  info "Demo API metric from Mimir"
  printf '%s\n' "$METRICS"
  info "Demo API logs from Loki"
  printf '%s\n' "$LOGS"
  info "Provisioned Grafana dashboard"
  printf '%s\n' "$DASHBOARD"
  info "Verification passed"
  printf 'Report: %s\n' "$REPORT"
  printf 'Dashboard: http://grafana.aiops.local/d/softcon-demo-api/softcon-demo-api\n'
} | tee "$REPORT"

unset ADMIN_PASSWORD
