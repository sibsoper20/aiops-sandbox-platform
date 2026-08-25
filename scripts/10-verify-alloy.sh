#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
sudo -v

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/softcon-aiops-alloy-$TIMESTAMP.log"
PORT_FORWARD_LOG="/tmp/softcon-mimir-alloy-port-forward-$TIMESTAMP.log"
PF_PID=""

cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

{
  info "Alloy workload"
  kctl -n observability rollout status deployment/alloy --timeout=180s
  kctl -n observability get deployment,pods,service \
    -l app.kubernetes.io/instance=alloy -o wide

  info "Recent Alloy logs"
  kctl -n observability logs deployment/alloy --tail=40
} | tee "$REPORT"

info "Starting temporary Mimir port forward"
kctl -n observability port-forward service/mimir 19009:9009 \
  >"$PORT_FORWARD_LOG" 2>&1 &
PF_PID="$!"

MIMIR_READY="false"
for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:19009/ready >/dev/null 2>&1; then
    MIMIR_READY="true"
    break
  fi
  sleep 1
done
[[ "$MIMIR_READY" == "true" ]] || fail "Mimir did not become reachable through the port forward"

query_mimir() {
  curl -fsS --get --data-urlencode "query=$1" \
    http://127.0.0.1:19009/prometheus/api/v1/query
}

info "Waiting for Alloy samples to reach Mimir"
NODE_RESULT=""
KSM_RESULT=""
for _ in {1..24}; do
  NODE_RESULT="$(query_mimir 'up{job="node-exporter"}')"
  KSM_RESULT="$(query_mimir 'up{job="kube-state-metrics"}')"
  if ! grep -q '"result":\[\]' <<<"$NODE_RESULT" &&
     ! grep -q '"result":\[\]' <<<"$KSM_RESULT"; then
    break
  fi
  sleep 5
done

grep -q '"status":"success"' <<<"$NODE_RESULT" || fail "Node Exporter query failed"
grep -q '"status":"success"' <<<"$KSM_RESULT" || fail "kube-state-metrics query failed"
grep -q '"result":\[\]' <<<"$NODE_RESULT" && fail "Mimir has no Node Exporter samples"
grep -q '"result":\[\]' <<<"$KSM_RESULT" && fail "Mimir has no kube-state-metrics samples"
grep -q '"value":\[[^]]*,"1"\]' <<<"$NODE_RESULT" || fail "Node Exporter target is not up"
grep -q '"value":\[[^]]*,"1"\]' <<<"$KSM_RESULT" || fail "kube-state-metrics target is not up"

NODE_INFO="$(query_mimir 'node_uname_info{cluster="softcon-aiops-lab",environment="lab"}')"
KUBE_INFO="$(query_mimir 'kube_node_info{cluster="softcon-aiops-lab",environment="lab"}')"
FILTER_RESULT="$(query_mimir 'node_filesystem_avail_bytes{fstype=~"tmpfs|devtmpfs|overlay|squashfs|fuse\\..*"}')"

grep -q '"result":\[\]' <<<"$NODE_INFO" && fail "Labeled node identity metric was not found"
grep -q '"result":\[\]' <<<"$KUBE_INFO" && fail "Labeled Kubernetes node metric was not found"
grep -q '"result":\[\]' <<<"$FILTER_RESULT" || fail "Noisy filesystem metrics were not filtered"

{
  info "Mimir scrape health: Node Exporter"
  printf '%s\n' "$NODE_RESULT"

  info "Mimir scrape health: kube-state-metrics"
  printf '%s\n' "$KSM_RESULT"

  info "Stable labels on node metrics"
  printf '%s\n' "$NODE_INFO"

  info "Stable labels on Kubernetes metrics"
  printf '%s\n' "$KUBE_INFO"

  info "Filtered filesystem query (expected empty result)"
  printf '%s\n' "$FILTER_RESULT"

  info "Verification passed"
  printf 'Report: %s\n' "$REPORT"
} | tee -a "$REPORT"
