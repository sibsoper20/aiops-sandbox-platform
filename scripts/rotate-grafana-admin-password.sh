#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_command openssl
sudo -v

kctl -n observability get deployment grafana >/dev/null 2>&1 ||
  fail "Grafana deployment not found. Deploy Grafana before rotating its password."

NEW_GRAFANA_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"

info "Resetting the Grafana administrator password"
kctl -n observability exec deployment/grafana -- \
  grafana cli admin reset-admin-password "$NEW_GRAFANA_PASSWORD"

info "Updating the Kubernetes Secret used by future Grafana deployments"
kctl -n observability create secret generic grafana-admin-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$NEW_GRAFANA_PASSWORD" \
  --dry-run=client -o yaml | kctl apply -f -

printf '\nPassword rotation completed.\n'
printf 'Grafana user: admin\n'
printf 'New password: %s\n' "$NEW_GRAFANA_PASSWORD"
printf '\nStore it securely. Do not paste it into chat, reports, or Git.\n'

unset NEW_GRAFANA_PASSWORD
