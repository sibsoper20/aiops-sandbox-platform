#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
sudo -v

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/softcon-aiops-node-exporter-$TIMESTAMP.log"
PORT_FORWARD_LOG="/tmp/softcon-node-exporter-port-forward-$TIMESTAMP.log"
METRICS_FILE="/tmp/softcon-node-exporter-$TIMESTAMP.txt"
PF_PID=""

cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

DAEMONSET_NAME="$(kctl -n observability get daemonset   -l app.kubernetes.io/name=prometheus-node-exporter   -o jsonpath='{.items[0].metadata.name}')"
SERVICE_NAME="$(kctl -n observability get service   -l app.kubernetes.io/name=prometheus-node-exporter   -o jsonpath='{.items[0].metadata.name}')"

[[ -n "$DAEMONSET_NAME" ]] || fail "Node Exporter DaemonSet was not found"
[[ -n "$SERVICE_NAME" ]] || fail "Node Exporter Service was not found"

{
  info "Node Exporter DaemonSet"
  kctl -n observability rollout status "daemonset/$DAEMONSET_NAME" --timeout=120s
  kctl -n observability get daemonset,pods,service     -l app.kubernetes.io/name=prometheus-node-exporter -o wide
} | tee "$REPORT"

info "Starting temporary Node Exporter port forward"
sudo k3s kubectl -n observability   port-forward "service/$SERVICE_NAME" 19100:9100   >"$PORT_FORWARD_LOG" 2>&1 &
PF_PID="$!"

METRICS_READY="false"
for _ in {1..20}; do
  if curl -fsS http://127.0.0.1:19100/metrics >"$METRICS_FILE" 2>/dev/null; then
    METRICS_READY="true"
    break
  fi
  sleep 1
done

[[ "$METRICS_READY" == "true" ]] || fail "Unable to reach the Node Exporter endpoint"

for metric in   node_uname_info   node_cpu_seconds_total   node_memory_MemAvailable_bytes   node_filesystem_avail_bytes
do
  grep -q "^$metric" "$METRICS_FILE" ||
    fail "Expected metric not found: $metric"
done

{
  info "Sample Node Exporter metrics"
  grep -E '^(node_uname_info|node_memory_MemAvailable_bytes|node_filesystem_avail_bytes)'     "$METRICS_FILE" | head -20 || true

  info "Verification passed"
  printf 'Report: %s\n' "$REPORT"
} | tee -a "$REPORT"

info "Review the report before recording Increment B as accepted"
