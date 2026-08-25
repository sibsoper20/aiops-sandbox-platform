#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
sudo -v

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/softcon-aiops-grafana-logs-$TIMESTAMP.log"
PORT_FORWARD_LOG="/tmp/softcon-grafana-logs-port-forward-$TIMESTAMP.log"
PF_PID=""

cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

ADMIN_USER="$(kctl -n observability get secret grafana-admin-credentials -o jsonpath='{.data.admin-user}' | base64 -d)"
ADMIN_PASSWORD="$(kctl -n observability get secret grafana-admin-credentials -o jsonpath='{.data.admin-password}' | base64 -d)"

kctl -n observability rollout status deployment/grafana --timeout=180s

info "Starting temporary Grafana port forward"
kctl -n observability port-forward service/grafana 13000:80 \
  >"$PORT_FORWARD_LOG" 2>&1 &
PF_PID="$!"

for _ in {1..30}; do
  curl -fsS http://127.0.0.1:13000/api/health >/dev/null 2>&1 && break
  sleep 1
done

DATASOURCE="$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASSWORD" \
  http://127.0.0.1:13000/api/datasources/uid/loki)"
DATASOURCE_HEALTH="$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASSWORD" \
  http://127.0.0.1:13000/api/datasources/uid/loki/health)"
DASHBOARD="$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASSWORD" \
  'http://127.0.0.1:13000/api/search?query=SOFTCON%20Kubernetes%20Logs')"
QUERY_RESULT="$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASSWORD" --get \
  --data-urlencode 'query={cluster="softcon-aiops-lab"}' \
  --data-urlencode 'limit=1' \
  http://127.0.0.1:13000/api/datasources/proxy/uid/loki/loki/api/v1/query_range)"

grep -q '"uid":"loki"' <<<"$DATASOURCE" || fail "Provisioned Loki data source was not found"
grep -Eiq '"status":"OK"|"message":.*success' <<<"$DATASOURCE_HEALTH" ||
  fail "Grafana did not report the Loki data source as healthy"
grep -q '"uid":"softcon-kubernetes-logs"' <<<"$DASHBOARD" ||
  fail "Provisioned Kubernetes logs dashboard was not found"
grep -q '"status":"success"' <<<"$QUERY_RESULT" ||
  fail "Grafana proxy did not return a successful Loki query"

{
  info "Provisioned Loki data source"
  printf '%s\n' "$DATASOURCE"

  info "Loki data source health"
  printf '%s\n' "$DATASOURCE_HEALTH"

  info "Provisioned Kubernetes logs dashboard"
  printf '%s\n' "$DASHBOARD"

  info "Loki query through Grafana"
  printf '%s\n' "$QUERY_RESULT"

  info "Verification passed"
  printf 'Report: %s\n' "$REPORT"
  printf 'Dashboard: http://grafana.aiops.local/d/softcon-kubernetes-logs/softcon-kubernetes-logs\n'
} | tee "$REPORT"

unset ADMIN_PASSWORD
