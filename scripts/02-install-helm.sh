#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
sudo systemctl is-active --quiet k3s || fail "k3s is not active. Run 00-install-k3s.sh first."

if command -v helm >/dev/null 2>&1; then
  info "Helm is already installed"
else
  info "Downloading the official Helm 4 installer"
  curl -fsSL     https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4     -o /tmp/softcon-get-helm-4.sh
  chmod 700 /tmp/softcon-get-helm-4.sh

  info "Installing Helm with checksum verification"
  /tmp/softcon-get-helm-4.sh
fi

KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"

info "Creating a protected user kubeconfig at $KUBECONFIG_PATH"
mkdir -p "$(dirname "$KUBECONFIG_PATH")"
sudo k3s kubectl config view --raw > "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"

export KUBECONFIG="$KUBECONFIG_PATH"

info "Helm version"
helm version

info "Testing Helm access to the cluster"
helm list -A

info "Stage 2 complete"
