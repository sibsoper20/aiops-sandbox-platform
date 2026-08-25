#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
sudo -v

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/softcon-aiops-kubernetes-logs-$TIMESTAMP.log"
PORT_FORWARD_LOG="/tmp/softcon-loki-log-validation-port-forward-$TIMESTAMP.log"
POD_NAME="logging-validation-$(date +%H%M%S)"
LOG_MESSAGE="softcon-kubernetes-log-$TIMESTAMP"
PF_PID=""

cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
  kctl -n demo delete pod "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

kctl -n observability rollout status deployment/alloy --timeout=180s
kctl -n observability rollout status statefulset/loki --timeout=180s

info "Creating a temporary validation pod"
kctl -n demo run "$POD_NAME" \
  --image=busybox:1.37.0 \
  --restart=Never \
  --labels=app.kubernetes.io/name=logging-validation \
  -- /bin/sh -c "echo '$LOG_MESSAGE'; sleep 45"

kctl -n demo wait --for=condition=Ready "pod/$POD_NAME" --timeout=120s

info "Starting temporary Loki gateway port forward"
kctl -n observability port-forward service/loki-gateway 13100:80 \
  >"$PORT_FORWARD_LOG" 2>&1 &
PF_PID="$!"

for _ in {1..30}; do
  curl -fsS http://127.0.0.1:13100/loki/api/v1/status/buildinfo >/dev/null 2>&1 && break
  sleep 1
done

QUERY_RESULT=""
for _ in {1..36}; do
  QUERY_RESULT="$(curl -fsS --get \
    --data-urlencode 'query={cluster="softcon-aiops-lab",namespace="demo",app="logging-validation"}' \
    --data-urlencode 'limit=20' \
    http://127.0.0.1:13100/loki/api/v1/query_range)"
  grep -q "$LOG_MESSAGE" <<<"$QUERY_RESULT" && break
  sleep 5
done

grep -q '"status":"success"' <<<"$QUERY_RESULT" || fail "Loki query did not succeed"
grep -q "$LOG_MESSAGE" <<<"$QUERY_RESULT" || fail "Validation pod log did not reach Loki"
grep -q '"namespace":"demo"' <<<"$QUERY_RESULT" || fail "Namespace label was not found"
grep -q '"pod":"logging-validation-' <<<"$QUERY_RESULT" || fail "Pod label was not found"
grep -q '"container":"logging-validation-' <<<"$QUERY_RESULT" || fail "Container label was not found"
grep -q '"app":"logging-validation"' <<<"$QUERY_RESULT" || fail "Application label was not found"
grep -q '"cluster":"softcon-aiops-lab"' <<<"$QUERY_RESULT" || fail "Cluster label was not found"
grep -q '"environment":"lab"' <<<"$QUERY_RESULT" || fail "Environment label was not found"

{
  info "Alloy and Loki workloads"
  kctl -n observability get deployment/alloy,statefulset/loki,pods \
    -l app.kubernetes.io/instance=alloy -o wide
  kctl -n observability get statefulset/loki,pods \
    -l app.kubernetes.io/instance=loki -o wide

  info "Validation pod"
  kctl -n demo get pod "$POD_NAME" --show-labels
  kctl -n demo logs "$POD_NAME"

  info "LogQL result with bounded labels"
  printf '%s\n' "$QUERY_RESULT"

  info "Verification passed"
  printf 'Report: %s\n' "$REPORT"
} | tee "$REPORT"
