#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
require_command helm
sudo systemctl is-active --quiet k3s || fail "k3s is not active"

GRAFANA_CHART_VERSION="${GRAFANA_CHART_VERSION:-10.5.15}"

kctl -n observability get deployment grafana >/dev/null 2>&1 ||
  fail "Grafana is not deployed. Complete scripts/11-deploy-grafana.sh first."
kctl -n observability get statefulset loki >/dev/null 2>&1 ||
  fail "Loki is not deployed. Complete scripts/13-deploy-loki.sh first."

info "Updating the Grafana dashboard ConfigMap"
kctl -n observability create configmap grafana-platform-dashboard \
  --from-file=platform-overview.json="$REPO_ROOT/observability/grafana/platform-overview.json" \
  --from-file=kubernetes-logs.json="$REPO_ROOT/observability/grafana/kubernetes-logs.json" \
  --dry-run=client -o yaml | kctl apply -f -

info "Grafana uses Recreate strategy for its single-writer SQLite volume"
info "The existing writable volume does not require the chart's chown initializer"

info "Updating Grafana provisioning"
helm repo add grafana-community https://grafana-community.github.io/helm-charts --force-update
helm repo update grafana-community

helm upgrade --install grafana grafana-community/grafana \
  --namespace observability \
  --version "$GRAFANA_CHART_VERSION" \
  --values "$REPO_ROOT/observability/grafana/values.yaml" \
  --wait --timeout 5m

info "Waiting for Grafana"
kctl -n observability rollout status deployment/grafana --timeout=300s

info "Stage 17 complete"
