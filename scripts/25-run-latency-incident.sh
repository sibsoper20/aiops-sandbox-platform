#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
sudo systemctl is-active --quiet k3s || fail "k3s is not active"

DELAY_MS="${DELAY_MS:-1500}"
DURATION_SECONDS="${DURATION_SECONDS:-90}"

[[ "$DELAY_MS" =~ ^[0-9]+$ ]] && ((DELAY_MS >= 100 && DELAY_MS <= 10000)) ||
  fail "DELAY_MS must be between 100 and 10000"
[[ "$DURATION_SECONDS" =~ ^[0-9]+$ ]] && ((DURATION_SECONDS >= 30 && DURATION_SECONDS <= 600)) ||
  fail "DURATION_SECONDS must be between 30 and 600"

kctl -n demo get deployment demo-api >/dev/null 2>&1 ||
  fail "Demo API is not deployed. Complete scripts/24-deploy-incident-capable-api.sh first."
kctl -n demo get deployment demo-traffic-generator >/dev/null 2>&1 ||
  fail "Traffic generator is not deployed. Complete scripts/22-enable-demo-telemetry.sh first."

RECOVERED="false"
recover() {
  if [[ "$RECOVERED" == "false" ]]; then
    info "Restoring the healthy API baseline"
    kctl -n demo set env deployment/demo-api \
      INCIDENT_DELAY_MS=0 INCIDENT_ERROR_PERCENT=0 >/dev/null
    kctl -n demo rollout status deployment/demo-api --timeout=300s
    RECOVERED="true"
  fi
}
trap recover EXIT

info "Injecting ${DELAY_MS} ms latency into API business endpoints"
kctl -n demo set env deployment/demo-api \
  INCIDENT_DELAY_MS="$DELAY_MS" INCIDENT_ERROR_PERCENT=0 >/dev/null
kctl -n demo rollout status deployment/demo-api --timeout=300s

info "Confirming probes remain healthy during the incident"
kctl -n demo exec deployment/demo-traffic-generator -- \
  wget -qO- http://demo-api.demo.svc.cluster.local:8080/readyz

info "Collecting incident evidence for ${DURATION_SECONDS} seconds"
printf 'Dashboard: http://grafana.aiops.local/d/softcon-demo-api/softcon-demo-api\n'
ELAPSED=0
while ((ELAPSED < DURATION_SECONDS)); do
  sleep 10
  ELAPSED=$((ELAPSED + 10))
  printf '  %d/%d seconds\n' "$ELAPSED" "$DURATION_SECONDS"
done

METRICS="$(kctl -n demo exec deployment/demo-traffic-generator -- \
  wget -qO- http://demo-api.demo.svc.cluster.local:8080/metrics)"
DELAY_COUNT="$(awk '/^demo_incident_delay_injections_total / {print $2}' <<<"$METRICS")"
[[ "$DELAY_COUNT" =~ ^[0-9]+$ ]] && ((DELAY_COUNT > 0)) ||
  fail "No delay injections were recorded"

INCIDENT_LOGS="$(kctl -n demo logs deployment/demo-api --tail=300 | \
  grep 'incident delay injected' || true)"
[[ -n "$INCIDENT_LOGS" ]] || fail "No latency incident logs were found"

info "Latency evidence"
printf 'Injected requests: %s\n' "$DELAY_COUNT"
printf '%s\n' "$INCIDENT_LOGS" | tail -5

recover

info "Confirming recovery"
kctl -n demo exec deployment/demo-traffic-generator -- \
  wget -qO- http://demo-api.demo.svc.cluster.local:8080/readyz

info "Stage 25 complete"
