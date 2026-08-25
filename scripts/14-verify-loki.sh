#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
sudo -v

kctl -n observability get statefulset loki >/dev/null 2>&1 ||
  fail "Loki StatefulSet not found. Run bash scripts/13-deploy-loki.sh first."

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/softcon-aiops-loki-$TIMESTAMP.log"
GATEWAY_PORT_FORWARD_LOG="/tmp/softcon-loki-gateway-port-forward-$TIMESTAMP.log"
DIRECT_PORT_FORWARD_LOG="/tmp/softcon-loki-direct-port-forward-$TIMESTAMP.log"
GATEWAY_PF_PID=""
DIRECT_PF_PID=""

cleanup() {
  if [[ -n "$GATEWAY_PF_PID" ]]; then
    kill "$GATEWAY_PF_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$DIRECT_PF_PID" ]]; then
    kill "$DIRECT_PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

{
  info "Loki workload and persistent storage"
  kctl -n observability rollout status statefulset/loki --timeout=180s
  kctl -n observability rollout status deployment/loki-gateway --timeout=180s
  kctl -n observability get statefulset,deployment,pods,service,pvc \
    -l app.kubernetes.io/instance=loki -o wide
} | tee "$REPORT"

PVC_NAME="$(kctl -n observability get pvc \
  -l app.kubernetes.io/instance=loki \
  -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$PVC_NAME" ]] || fail "Loki persistent volume claim was not found"

PVC_STATUS="$(kctl -n observability get pvc "$PVC_NAME" -o jsonpath='{.status.phase}')"
[[ "$PVC_STATUS" == "Bound" ]] || fail "Loki PVC is not Bound"

info "Starting temporary direct Loki port forward for readiness"
kctl -n observability port-forward statefulset/loki 13101:3100 \
  >"$DIRECT_PORT_FORWARD_LOG" 2>&1 &
DIRECT_PF_PID="$!"

LOKI_READY="false"
for _ in {1..60}; do
  if curl -fsS http://127.0.0.1:13101/ready >/tmp/softcon-loki-ready.txt 2>/dev/null; then
    LOKI_READY="true"
    break
  fi
  sleep 1
done
[[ "$LOKI_READY" == "true" ]] || fail "Direct Loki readiness endpoint did not become available"

info "Starting temporary Loki gateway port forward for API validation"
kctl -n observability port-forward service/loki-gateway 13100:80 \
  >"$GATEWAY_PORT_FORWARD_LOG" 2>&1 &
GATEWAY_PF_PID="$!"

GATEWAY_READY="false"
for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:13100/loki/api/v1/status/buildinfo \
    >/tmp/softcon-loki-buildinfo.json 2>/dev/null; then
    GATEWAY_READY="true"
    break
  fi
  sleep 1
done
[[ "$GATEWAY_READY" == "true" ]] || fail "Loki API was not reachable through the gateway"

LOG_TIME="$(date +%s%N)"
LOG_MESSAGE="softcon-loki-validation-$TIMESTAMP"
PUSH_BODY="$(printf '{"streams":[{"stream":{"job":"softcon-loki-validation","cluster":"softcon-aiops-lab"},"values":[["%s","%s"]]}]}' "$LOG_TIME" "$LOG_MESSAGE")"

curl -fsS -X POST \
  -H 'Content-Type: application/json' \
  --data "$PUSH_BODY" \
  http://127.0.0.1:13100/loki/api/v1/push

QUERY_RESULT=""
for _ in {1..30}; do
  QUERY_RESULT="$(curl -fsS --get \
    --data-urlencode 'query={job="softcon-loki-validation"}' \
    --data-urlencode 'limit=10' \
    http://127.0.0.1:13100/loki/api/v1/query_range)"
  grep -q "$LOG_MESSAGE" <<<"$QUERY_RESULT" && break
  sleep 2
done

grep -q '"status":"success"' <<<"$QUERY_RESULT" || fail "Loki query did not succeed"
grep -q "$LOG_MESSAGE" <<<"$QUERY_RESULT" || fail "Synthetic validation log was not returned"

{
  info "Loki readiness"
  cat /tmp/softcon-loki-ready.txt

  info "Loki API through gateway"
  cat /tmp/softcon-loki-buildinfo.json

  info "Loki persistent volume"
  printf 'PVC: %s\nStatus: %s\n' "$PVC_NAME" "$PVC_STATUS"

  info "Synthetic push and query"
  printf '%s\n' "$QUERY_RESULT"

  info "Verification passed"
  printf 'Report: %s\n' "$REPORT"
} | tee -a "$REPORT"
