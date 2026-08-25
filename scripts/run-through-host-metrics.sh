#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/run-through-kubernetes-metrics.sh"
bash "$SCRIPT_DIR/05-deploy-node-exporter.sh"
bash "$SCRIPT_DIR/06-verify-node-exporter.sh"
