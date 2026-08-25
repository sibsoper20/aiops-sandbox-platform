#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
sudo -v

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/softcon-aiops-kubernetes-metrics-$TIMESTAMP.log"
PORT_FORWARD_LOG="/tmp/softcon-kube-state-metrics-port-forward-$TIMESTAMP.log"
PF_PID=""

cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

{
  info "k3s service"
  sudo systemctl is-active k3s

  info "Kubernetes node"
  kctl get nodes -o wide

  info "Foundation deployment"
  kctl -n demo get deployment,pods,service,ingress -o wide
  kctl -n demo rollout status deployment/foundation-test --timeout=120s

  info "Ingress response"
  curl -sS -o /dev/null -w 'HTTP %{http_code}\n'     -H 'Host: aiops-demo.local' http://127.0.0.1

  info "Node resource metrics"
  kctl top nodes

  info "Pod resource metrics"
  kctl top pods -A

  info "kube-state-metrics resources"
  kctl -n observability get deployment,pods,service     -l app.kubernetes.io/name=kube-state-metrics -o wide
  kctl -n observability rollout status deployment/kube-state-metrics --timeout=120s
} | tee "$REPORT"

info "Starting temporary kube-state-metrics port forward"
sudo k3s kubectl -n observability   port-forward service/kube-state-metrics 18081:8080   >"$PORT_FORWARD_LOG" 2>&1 &
PF_PID="$!"

for _ in {1..20}; do
  if curl -fsS http://127.0.0.1:18081/metrics >/tmp/softcon-kube-state-metrics.txt; then
    break
  fi
  sleep 1
done

grep -q '^kube_' /tmp/softcon-kube-state-metrics.txt ||
  fail "kube-state-metrics endpoint did not return kube_* metrics"

{
  info "Sample kube-state-metrics output"
  grep -E '^(kube_node_info|kube_pod_info|kube_deployment_status_replicas)'     /tmp/softcon-kube-state-metrics.txt | head -20 || true

  info "Verification passed"
  printf 'Report: %s\n' "$REPORT"
} | tee -a "$REPORT"

info "Review the report before recording the phase as accepted"
