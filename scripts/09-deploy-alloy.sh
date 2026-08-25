#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
require_command helm
sudo systemctl is-active --quiet k3s || fail "k3s is not active"

ALLOY_CHART_VERSION="${ALLOY_CHART_VERSION:-1.12.0}"

info "Creating or updating the Alloy configuration"
kctl -n observability create configmap alloy-config \
  --from-file=config.alloy="$REPO_ROOT/observability/alloy/config.alloy" \
  --dry-run=client -o yaml | kctl apply -f -

info "Adding the Grafana Helm repository"
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update grafana

info "Rendering the Alloy chart before installation"
helm template alloy grafana/alloy \
  --namespace observability \
  --version "$ALLOY_CHART_VERSION" \
  --values "$REPO_ROOT/observability/alloy/values.yaml" \
  >/tmp/softcon-aiops-alloy-rendered.yaml

info "Deploying Grafana Alloy"
helm upgrade --install alloy grafana/alloy \
  --namespace observability \
  --version "$ALLOY_CHART_VERSION" \
  --values "$REPO_ROOT/observability/alloy/values.yaml" \
  --wait --timeout 5m

info "Waiting for Alloy"
kctl -n observability rollout status deployment/alloy --timeout=300s

info "Alloy resources"
kctl -n observability get deployment,pods,service \
  -l app.kubernetes.io/instance=alloy -o wide

info "Stage 9 complete"
