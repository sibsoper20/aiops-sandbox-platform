#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
sudo -v

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/softcon-aiops-grafana-$TIMESTAMP.log"
PORT_FORWARD_LOG="/tmp/softcon-grafana-port-forward-$TIMESTAMP.log"
PF_PID=""

cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

ADMIN_USER="$(kctl -n observability get secret grafana-admin-credentials -o jsonpath='{.data.admin-user}' | base64 -d)"
ADMIN_PASSWORD="$(kctl -n observability get secret grafana-admin-credentials -o jsonpath='{.data.admin-password}' | base64 -d)"

{
  info "Grafana workload and persistent storage"
  kctl -n observability rollout status deployment/grafana --timeout=180s
  kctl -n observability get deployment,pods,service,ingress,pvc \
    -l app.kubernetes.io/instance=grafana -o wide
} | tee "$REPORT"

info "Starting temporary Grafana port forward"
kctl -n observability port-forward service/grafana 13000:80 \
  >"$PORT_FORWARD_LOG" 2>&1 &
PF_PID="$!"

GRAFANA_READY="false"
for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:13000/api/health >/tmp/softcon-grafana-health.json 2>/dev/null; then
    GRAFANA_READY="true"
    break
  fi
  sleep 1
done
[[ "$GRAFANA_READY" == "true" ]] || fail "Grafana health endpoint did not become available"

DATASOURCE="$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASSWORD" \
  http://127.0.0.1:13000/api/datasources/uid/mimir)"
DASHBOARD="$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASSWORD" \
  'http://127.0.0.1:13000/api/search?query=SOFTCON%20AIOps%20Platform%20Overview')"

grep -q '"uid":"mimir"' <<<"$DATASOURCE" || fail "Provisioned Mimir data source was not found"
grep -q '"uid":"softcon-platform-overview"' <<<"$DASHBOARD" || fail "Provisioned platform dashboard was not found"

INGRESS_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' \
  -H 'Host: grafana.aiops.local' http://127.0.0.1/ || true)"
[[ "$INGRESS_STATUS" =~ ^(200|302)$ ]] || fail "Grafana ingress returned HTTP $INGRESS_STATUS"

{
  info "Grafana health"
  cat /tmp/softcon-grafana-health.json

  info "Provisioned Mimir data source"
  printf '%s\n' "$DATASOURCE"

  info "Provisioned dashboard"
  printf '%s\n' "$DASHBOARD"

  info "Grafana ingress"
  printf 'HTTP %s\n' "$INGRESS_STATUS"

  info "Verification passed"
  printf 'Report: %s\n' "$REPORT"
  printf 'URL: http://grafana.aiops.local\n'
  printf 'Local admin user: %s\n' "$ADMIN_USER"
  printf 'Local admin password: %s\n' "$ADMIN_PASSWORD"
} | tee -a "$REPORT"

printf '\nTreat the displayed password as a local lab credential. Do not commit or share the report.\n'
