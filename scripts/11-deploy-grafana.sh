#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
require_command helm
require_command openssl
sudo systemctl is-active --quiet k3s || fail "k3s is not active"

GRAFANA_CHART_VERSION="${GRAFANA_CHART_VERSION:-10.5.15}"

if ! kctl -n observability get secret grafana-admin-credentials >/dev/null 2>&1; then
  info "Creating the Grafana administrator secret"
  GRAFANA_ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"
  kctl -n observability create secret generic grafana-admin-credentials \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD"
  unset GRAFANA_ADMIN_PASSWORD
else
  info "Keeping the existing Grafana administrator secret"
fi

info "Creating or updating the dashboard ConfigMap"
kctl -n observability create configmap grafana-platform-dashboard \
  --from-file=platform-overview.json="$REPO_ROOT/observability/grafana/platform-overview.json" \
  --dry-run=client -o yaml | kctl apply -f -

info "Adding the maintained Grafana Community Helm repository"
helm repo add grafana-community https://grafana-community.github.io/helm-charts --force-update
helm repo update grafana-community

info "Rendering the Grafana chart before installation"
helm template grafana grafana-community/grafana \
  --namespace observability \
  --version "$GRAFANA_CHART_VERSION" \
  --values "$REPO_ROOT/observability/grafana/values.yaml" \
  >/tmp/softcon-aiops-grafana-rendered.yaml

info "Deploying Grafana"
helm upgrade --install grafana grafana-community/grafana \
  --namespace observability \
  --version "$GRAFANA_CHART_VERSION" \
  --values "$REPO_ROOT/observability/grafana/values.yaml" \
  --wait --timeout 5m

info "Waiting for Grafana"
kctl -n observability rollout status deployment/grafana --timeout=300s

info "Grafana resources"
kctl -n observability get deployment,pods,service,ingress,pvc \
  -l app.kubernetes.io/instance=grafana -o wide

info "Stage 11 complete"
printf '\nGrafana URL after local DNS setup: http://grafana.aiops.local\n'
printf 'Use scripts/12-verify-grafana.sh to verify and retrieve the local admin login.\n'
