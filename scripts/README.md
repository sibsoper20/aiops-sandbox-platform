# Setup scripts

These scripts build the currently supported SOFTCON 2027 AIOps lab in small, understandable stages.

They are written for:

- Pop!_OS or Ubuntu
- A single-node k3s cluster
- The `softcon-2027` branch
- A learner running commands directly on the Kubernetes host

The scripts are safe to rerun where practical. They stop when a required check fails. They do not uninstall software, delete the cluster, or embed credentials.

## What is currently automated

| Stage | Script | Result |
|---|---|---|
| 0 | `00-install-k3s.sh` | Installs prerequisites and k3s if missing |
| 1 | `01-deploy-foundation.sh` | Creates namespaces and deploys the validation application |
| 2 | `02-install-helm.sh` | Installs Helm 4 and creates a protected user kubeconfig |
| 3 | `03-deploy-kubernetes-metrics.sh` | Validates k3s Metrics Server and deploys kube-state-metrics |
| 4 | `04-verify-kubernetes-metrics.sh` | Runs read-only checks and writes a report under `/tmp` |
| 5 | `05-deploy-node-exporter.sh` | Deploys host metrics collection as a DaemonSet |
| 6 | `06-verify-node-exporter.sh` | Confirms CPU, memory, filesystem, and host metrics |
| 7 | `07-deploy-mimir.sh` | Deploys persistent single-process Mimir for the lab |
| 8 | `08-verify-mimir.sh` | Checks Mimir storage, readiness, and query API |
| 9 | `09-deploy-alloy.sh` | Deploys Alloy and its metrics collection pipeline |
| 10 | `10-verify-alloy.sh` | Proves both metric sources reach Mimir with labels and filtering |
| 11 | `11-deploy-grafana.sh` | Deploys persistent Grafana with Mimir and a dashboard |
| 12 | `12-verify-grafana.sh` | Checks health, provisioning, ingress, and storage |

Later scripts will add Loki, the incident simulator, and the local AI investigation workflow. Those phases are not yet represented as working scripts.

## Start from scratch

### 1. Install Git and clone the repository

```bash
sudo apt update
sudo apt install -y git
mkdir -p ~/projects
cd ~/projects
git clone --branch softcon-2027 --single-branch \
  https://github.com/sibsoper20/aiops-sandbox-platform.git
cd aiops-sandbox-platform
```

If you already cloned the repository:

```bash
cd ~/projects/aiops-sandbox-platform
git switch softcon-2027
git pull origin softcon-2027
```

### 2. Run each stage separately

Running stages one at a time is recommended for learning:

```bash
bash scripts/00-install-k3s.sh
bash scripts/01-deploy-foundation.sh
bash scripts/02-install-helm.sh
bash scripts/03-deploy-kubernetes-metrics.sh
bash scripts/04-verify-kubernetes-metrics.sh
bash scripts/05-deploy-node-exporter.sh
bash scripts/06-verify-node-exporter.sh
bash scripts/07-deploy-mimir.sh
bash scripts/08-verify-mimir.sh
bash scripts/09-deploy-alloy.sh
bash scripts/10-verify-alloy.sh
bash scripts/11-deploy-grafana.sh
bash scripts/12-verify-grafana.sh
```

Read the output after each stage before continuing.

### 3. Optional combined runner

After reading the individual scripts, you can run through Kubernetes object metrics:

```bash
bash scripts/run-through-kubernetes-metrics.sh
```

To include host metrics through Node Exporter:

```bash
bash scripts/run-through-host-metrics.sh
```

## Configuration

Optional environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `K3S_CHANNEL` | `stable` | k3s release channel used for a new installation |
| `K3S_VERSION` | empty | Exact k3s version; overrides the channel when supplied |
| `KSM_CHART_VERSION` | `8.4.0` | kube-state-metrics Helm chart version |
| `NODE_EXPORTER_CHART_VERSION` | `4.56.1` | Node Exporter Helm chart version |
| `ALLOY_CHART_VERSION` | `1.12.0` | Grafana Alloy Helm chart version |
| `GRAFANA_CHART_VERSION` | `10.5.15` | Grafana Community Helm chart version |
| `KUBECONFIG` | `$HOME/.kube/config` | User kubeconfig used by Helm |

Example with an exact k3s version:

```bash
K3S_VERSION="vX.Y.Z+k3s1" bash scripts/00-install-k3s.sh
```

Replace the example with a reviewed release from the official k3s releases page.

## Expected verification

The final script checks:

- k3s service is active
- Kubernetes node is Ready
- Foundation application is available
- Ingress returns HTTP 200
- `kubectl top nodes` returns resource metrics
- `kubectl top pods -A` returns resource metrics
- kube-state-metrics is available
- kube-state-metrics exposes `kube_*` metrics
- Node Exporter runs on the Kubernetes node
- Node Exporter exposes CPU, memory, filesystem, and host identity metrics
- Mimir uses a Bound persistent volume
- Mimir readiness and PromQL query endpoints respond successfully
- Alloy scrapes Node Exporter and kube-state-metrics
- Mimir contains both metric streams with stable lab labels
- Temporary, tmpfs, and FUSE filesystem metrics are filtered
- Grafana is healthy and uses persistent storage
- Mimir and the platform dashboard are provisioned automatically
- Grafana ingress responds at `grafana.aiops.local`

It writes a timestamped report to:

```text
/tmp/softcon-aiops-<stage>-<timestamp>.log
```

Review that report yourself. The script does not automatically claim that a phase is accepted.

## Important security notes

- `$HOME/.kube/config` contains cluster credentials. The setup script sets its permissions to `600`.
- Never commit kubeconfig, tokens, private keys, passwords, or local `.env` files.
- Review remote installer scripts before running them.
- This is a learning and conference demonstration environment, not a production high-availability setup.
- The validation workload currently uses a mutable test image. A reviewed digest should be pinned before the demo is frozen.

## Troubleshooting

Cluster status:

```bash
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
```

Recent events:

```bash
sudo k3s kubectl get events -A \
  --sort-by=.metadata.creationTimestamp
```

k3s logs:

```bash
sudo journalctl -u k3s -n 200 --no-pager
```

Metrics Server logs:

```bash
sudo k3s kubectl -n kube-system \
  logs deployment/metrics-server
```

kube-state-metrics logs:

```bash
sudo k3s kubectl -n observability \
  logs deployment/kube-state-metrics
```

Alloy logs:

```bash
sudo k3s kubectl -n observability logs deployment/alloy --tail=100
```

Grafana logs:

```bash
sudo k3s kubectl -n observability logs deployment/grafana --tail=100
```

Retrieve the local Grafana password without storing it in Git:

```bash
sudo k3s kubectl -n observability get secret grafana-admin-credentials \
  -o jsonpath='{.data.admin-password}' | base64 -d
echo
```

Helm releases:

```bash
helm list -A
```

## Cleanup

Cleanup is deliberately manual so learners can see what is being removed.

Remove Grafana while retaining its persistent volume:

```bash
helm uninstall grafana -n observability
sudo k3s kubectl -n observability delete configmap grafana-platform-dashboard
```

Keep `grafana-admin-credentials` if you plan to reinstall. Deleting it changes the local login on the next deployment.

Remove Alloy:

```bash
helm uninstall alloy -n observability
sudo k3s kubectl -n observability delete configmap alloy-config
```

Remove Mimir while retaining its persistent volume:

```bash
sudo k3s kubectl -n observability delete deployment/mimir service/mimir configmap/mimir-config
```

Deleting the `mimir-data` PVC also deletes stored lab metrics and must be an intentional action.

Remove Node Exporter:

```bash
helm uninstall prometheus-node-exporter -n observability
```

Remove kube-state-metrics:

```bash
helm uninstall kube-state-metrics -n observability
```

Remove the foundation workload:

```bash
sudo k3s kubectl delete -f platform/k3s/test-workload.yaml
```

Do not uninstall k3s unless you intend to remove the entire cluster.
