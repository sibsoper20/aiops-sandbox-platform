#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
sudo -v

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/softcon-aiops-mimir-$TIMESTAMP.log"
PORT_FORWARD_LOG="/tmp/softcon-mimir-port-forward-$TIMESTAMP.log"
PF_PID=""

cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

{
  info "Mimir workload and persistent storage"
  kctl -n observability rollout status deployment/mimir --timeout=180s
  kctl -n observability get deployment,pods,service,pvc     -l app.kubernetes.io/name=mimir -o wide

  PVC_STATUS="$(kctl -n observability get pvc mimir-data -o jsonpath='{.status.phase}')"
  printf 'PVC status: %s\n' "$PVC_STATUS"
  [[ "$PVC_STATUS" == "Bound" ]] || fail "Mimir PVC is not Bound"
} | tee "$REPORT"

info "Starting temporary Mimir port forward"
sudo k3s kubectl -n observability   port-forward service/mimir 19009:9009   >"$PORT_FORWARD_LOG" 2>&1 &
PF_PID="$!"

MIMIR_READY="false"
for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:19009/ready >/tmp/softcon-mimir-ready.txt 2>/dev/null; then
    MIMIR_READY="true"
    break
  fi
  sleep 1
done
[[ "$MIMIR_READY" == "true" ]] || fail "Mimir readiness endpoint did not become available"

QUERY_RESULT="$(curl -fsS   --get   --data-urlencode 'query=vector(1)'   http://127.0.0.1:19009/prometheus/api/v1/query)"

grep -q '"status":"success"' <<<"$QUERY_RESULT" ||
  fail "Mimir query API did not return success"

{
  info "Mimir readiness"
  cat /tmp/softcon-mimir-ready.txt

  info "Mimir test query: vector(1)"
  printf '%s\n' "$QUERY_RESULT"

  info "Verification passed"
  printf 'Report: %s\n' "$REPORT"
} | tee -a "$REPORT"

info "Metric ingestion and persistence will be validated after Alloy is connected"
