#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
require_command helm
require_command curl

KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
[[ -f "$KUBECONFIG_PATH" ]] ||
  fail "Kubeconfig not found at $KUBECONFIG_PATH. Run 02-install-helm.sh first."
export KUBECONFIG="$KUBECONFIG_PATH"

KSM_CHART_VERSION="${KSM_CHART_VERSION:-8.4.0}"

info "Checking the k3s-provided Metrics Server"
kctl -n kube-system rollout status deployment/metrics-server --timeout=180s

if ! kctl top nodes; then
  info "Metrics may still be warming up; waiting 60 seconds"
  sleep 60
  kctl top nodes || fail "kubectl top nodes failed. Inspect Metrics Server before continuing."
fi

info "Adding the Prometheus Community Helm repository"
helm repo add prometheus-community   https://prometheus-community.github.io/helm-charts   --force-update
helm repo update

info "Rendering kube-state-metrics chart version $KSM_CHART_VERSION"
helm template kube-state-metrics   prometheus-community/kube-state-metrics   --namespace observability   --version "$KSM_CHART_VERSION"   --values "$REPO_ROOT/observability/kube-state-metrics/values.yaml"   > /tmp/softcon-kube-state-metrics-rendered.yaml

info "Installing or upgrading kube-state-metrics"
helm upgrade --install kube-state-metrics   prometheus-community/kube-state-metrics   --namespace observability   --create-namespace   --version "$KSM_CHART_VERSION"   --values "$REPO_ROOT/observability/kube-state-metrics/values.yaml"   --wait   --timeout 5m

info "Waiting for kube-state-metrics"
kctl -n observability rollout status deployment/kube-state-metrics --timeout=180s

info "Stage 3 complete"
