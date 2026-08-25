#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
require_command helm

KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
[[ -f "$KUBECONFIG_PATH" ]] ||
  fail "Kubeconfig not found at $KUBECONFIG_PATH. Run 02-install-helm.sh first."
export KUBECONFIG="$KUBECONFIG_PATH"

NODE_EXPORTER_CHART_VERSION="${NODE_EXPORTER_CHART_VERSION:-4.56.1}"

info "Adding the Prometheus Community Helm repository"
helm repo add prometheus-community   https://prometheus-community.github.io/helm-charts   --force-update
helm repo update

info "Rendering Node Exporter chart version $NODE_EXPORTER_CHART_VERSION"
helm template prometheus-node-exporter   prometheus-community/prometheus-node-exporter   --namespace observability   --version "$NODE_EXPORTER_CHART_VERSION"   --values "$REPO_ROOT/observability/node-exporter/values.yaml"   > /tmp/softcon-node-exporter-rendered.yaml

info "Installing or upgrading Node Exporter"
helm upgrade --install prometheus-node-exporter   prometheus-community/prometheus-node-exporter   --namespace observability   --create-namespace   --version "$NODE_EXPORTER_CHART_VERSION"   --values "$REPO_ROOT/observability/node-exporter/values.yaml"   --wait   --timeout 5m

DAEMONSET_NAME="$(kctl -n observability get daemonset   -l app.kubernetes.io/name=prometheus-node-exporter   -o jsonpath='{.items[0].metadata.name}')"

[[ -n "$DAEMONSET_NAME" ]] || fail "Node Exporter DaemonSet was not found"

info "Waiting for Node Exporter DaemonSet: $DAEMONSET_NAME"
kctl -n observability rollout status "daemonset/$DAEMONSET_NAME" --timeout=180s

info "Node Exporter resources"
kctl -n observability get daemonset,pods,service   -l app.kubernetes.io/name=prometheus-node-exporter -o wide

info "Stage 5 complete"
