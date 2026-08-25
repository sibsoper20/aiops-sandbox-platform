#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
require_command go
require_command curl

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/softcon-aiops-demo-api-source-$TIMESTAMP.log"
APP_LOG="/tmp/softcon-demo-api-$TIMESTAMP.json.log"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cd "$REPO_ROOT/apps/demo-api"

{
  info "Go version"
  go version

  info "Downloading application dependencies"
  go mod download

  info "Formatting check"
  UNFORMATTED="$(gofmt -l .)"
  [[ -z "$UNFORMATTED" ]] || fail "Files require gofmt: $UNFORMATTED"
  printf 'Go formatting passed\n'

  info "Unit and HTTP handler tests"
  go test -race -cover ./...

  info "Go vet"
  go vet ./...
} | tee "$REPORT"

info "Starting the API with in-memory storage"
PORT=18080 go run . >"$APP_LOG" 2>&1 &
APP_PID="$!"

APP_READY="false"
for _ in {1..60}; do
  if curl -fsS http://127.0.0.1:18080/readyz >/tmp/softcon-demo-api-ready.json 2>/dev/null; then
    APP_READY="true"
    break
  fi
  sleep 1
done
[[ "$APP_READY" == "true" ]] || fail "Demo API did not become ready"

HEALTH="$(curl -fsS http://127.0.0.1:18080/healthz)"
READY="$(curl -fsS http://127.0.0.1:18080/readyz)"
CREATED="$(curl -fsS -X POST \
  -H 'Content-Type: application/json' \
  --data '{"product":"SOFTCON Coffee","quantity":2}' \
  http://127.0.0.1:18080/api/orders)"
ORDERS="$(curl -fsS http://127.0.0.1:18080/api/orders)"
METRICS="$(curl -fsS http://127.0.0.1:18080/metrics)"

grep -q '"status":"ok"' <<<"$HEALTH" || fail "Health response was unexpected"
grep -q '"status":"ready"' <<<"$READY" || fail "Readiness response was unexpected"
grep -q '"product":"SOFTCON Coffee"' <<<"$CREATED" || fail "Order creation failed"
grep -q '"product":"SOFTCON Coffee"' <<<"$ORDERS" || fail "Created order was not returned"
grep -q 'demo_http_requests_total' <<<"$METRICS" || fail "Request metric was not exposed"
grep -q 'demo_orders_created_total 1' <<<"$METRICS" || fail "Order counter was not updated"

sleep 1
grep -q '"msg":"request completed"' "$APP_LOG" || fail "Structured request log was not emitted"
grep -q '"storage":"memory"' "$APP_LOG" || fail "Storage context was not present in logs"

{
  info "Health"
  printf '%s\n' "$HEALTH"

  info "Readiness"
  printf '%s\n' "$READY"

  info "Created order"
  printf '%s\n' "$CREATED"

  info "Order list"
  printf '%s\n' "$ORDERS"

  info "Application metrics"
  printf '%s\n' "$METRICS"

  info "Structured application logs"
  tail -10 "$APP_LOG"

  info "Verification passed"
  printf 'Report: %s\n' "$REPORT"
} | tee -a "$REPORT"
