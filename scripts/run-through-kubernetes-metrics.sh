#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/00-install-k3s.sh"
bash "$SCRIPT_DIR/01-deploy-foundation.sh"
bash "$SCRIPT_DIR/02-install-helm.sh"
bash "$SCRIPT_DIR/03-deploy-kubernetes-metrics.sh"
bash "$SCRIPT_DIR/04-verify-kubernetes-metrics.sh"
