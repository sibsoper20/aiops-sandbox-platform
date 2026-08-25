#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

info "Installing required operating-system packages"
sudo apt update
sudo apt install -y ca-certificates curl git openssl

if command -v k3s >/dev/null 2>&1; then
  info "k3s is already installed; leaving the existing installation unchanged"
else
  info "Downloading the official k3s installer for review"
  curl -fsSL https://get.k3s.io -o /tmp/softcon-get-k3s.sh
  chmod 700 /tmp/softcon-get-k3s.sh

  if [[ -n "${K3S_VERSION:-}" ]]; then
    info "Installing requested k3s version: $K3S_VERSION"
    sudo env INSTALL_K3S_VERSION="$K3S_VERSION" /tmp/softcon-get-k3s.sh
  else
    K3S_CHANNEL="${K3S_CHANNEL:-stable}"
    info "Installing k3s from channel: $K3S_CHANNEL"
    sudo env INSTALL_K3S_CHANNEL="$K3S_CHANNEL" /tmp/softcon-get-k3s.sh
  fi
fi

info "Checking the k3s service"
sudo systemctl is-active --quiet k3s || fail "k3s service is not active"

wait_for_node

info "Installed k3s version"
sudo k3s --version

info "Node status"
kctl get nodes -o wide

info "Stage 0 complete"
