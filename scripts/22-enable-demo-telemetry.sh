#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
require_command helm
sudo systemctl is-active --quiet k3s || fail "k3s is not active"

ALLOY_CHART_VERSION="${ALLOY_CHART_VERSION:-1.12.0}"

kctl -n demo get deployment demo-api >/dev/null 2>&1 ||
  fail "Demo API is not deployed. Complete scripts/20-deploy-demo-application.sh first."

info "Applying the demo API traffic generator"
kctl apply -f "$REPO_ROOT/apps/demo-api/kubernetes/traffic-generator.yaml"
kctl -n demo rollout status deployment/demo-traffic-generator --timeout=180s

info "Updating Alloy with the demo API metrics scrape"
kctl -n observability create configmap alloy-config \
  --from-file=config.alloy="$REPO_ROOT/observability/alloy/config.alloy" \
  --dry-run=client -o yaml | kctl apply -f -
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update grafana
helm upgrade --install alloy grafana/alloy \
  --namespace observability \
  --version "$ALLOY_CHART_VERSION" \
  --values "$REPO_ROOT/observability/alloy/values.yaml" \
  --wait --timeout 5m
kctl -n observability rollout status deployment/alloy --timeout=300s

info "Provisioning the demo API dashboard"
bash "$REPO_ROOT/scripts/17-configure-grafana-logs.sh"

info "Stage 22 complete"
