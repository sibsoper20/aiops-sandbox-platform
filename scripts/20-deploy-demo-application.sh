#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_repo_root
require_command openssl
sudo systemctl is-active --quiet k3s || fail "k3s is not active"

if ! kctl -n demo get secret demo-postgres-credentials >/dev/null 2>&1; then
  info "Creating the PostgreSQL credential Secret"
  POSTGRES_PASSWORD="$(openssl rand -hex 24)"
  kctl -n demo create secret generic demo-postgres-credentials \
    --from-literal=username=demo \
    --from-literal=password="$POSTGRES_PASSWORD"
  unset POSTGRES_PASSWORD
else
  info "Keeping the existing PostgreSQL credential Secret"
fi

info "Deploying persistent PostgreSQL 18.6"
kctl apply -f "$REPO_ROOT/apps/demo-api/kubernetes/postgres.yaml"

info "Waiting for PostgreSQL"
kctl -n demo rollout status statefulset/demo-postgres --timeout=300s

info "Deploying the demo order API"
kctl apply -f "$REPO_ROOT/apps/demo-api/kubernetes/api.yaml"
kctl -n demo rollout restart deployment/demo-api
kctl -n demo rollout status deployment/demo-api --timeout=300s

info "Demo application resources"
kctl -n demo get statefulset,deployment,pods,service,ingress,pvc \
  -l app.kubernetes.io/part-of=softcon-aiops-demo -o wide

info "Stage 20 complete"
printf '\nLocal URL after hosts setup: http://orders.aiops.local\n'
