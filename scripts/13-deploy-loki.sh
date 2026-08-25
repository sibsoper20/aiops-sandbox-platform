#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
require_command helm
sudo systemctl is-active --quiet k3s || fail "k3s is not active"

LOKI_CHART_VERSION="${LOKI_CHART_VERSION:-18.7.6}"

info "Adding the maintained Grafana Community Helm repository"
helm repo add grafana-community https://grafana-community.github.io/helm-charts --force-update
helm repo update grafana-community

info "Rendering the Loki chart before installation"
helm template loki grafana-community/loki \
  --namespace observability \
  --version "$LOKI_CHART_VERSION" \
  --values "$REPO_ROOT/observability/loki/values.yaml" \
  >/tmp/softcon-aiops-loki-rendered.yaml

info "Deploying persistent monolithic Loki"
helm upgrade --install loki grafana-community/loki \
  --namespace observability \
  --version "$LOKI_CHART_VERSION" \
  --values "$REPO_ROOT/observability/loki/values.yaml" \
  --wait --timeout 8m

info "Waiting for Loki"
kctl -n observability rollout status statefulset/loki --timeout=480s
kctl -n observability rollout status deployment/loki-gateway --timeout=300s

info "Loki resources"
kctl -n observability get statefulset,deployment,pods,service,pvc \
  -l app.kubernetes.io/instance=loki -o wide

info "Stage 13 complete"
