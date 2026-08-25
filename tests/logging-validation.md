# Logging validation

- Date: 2026-08-25
- Tester: Jesse Jadraque
- Host: UM780 XTX (`pop-os`)
- Branch: `softcon-2027`

## Increment A — Loki storage

| Check | Result | Evidence |
|---|---|---|
| Loki monolithic workload is available | Pass | StatefulSet ready 1/1; pod running with zero restarts. |
| Loki gateway is available | Pass | Deployment ready 1/1; API returned Loki 3.7.6 build information. |
| Loki persistent volume is Bound | Pass | `storage-loki-0` is Bound with 10 GiB on `local-path`. |
| Loki readiness endpoint succeeds | Pass | Direct `/ready` returned `ready`. |
| Synthetic log push succeeds | Pass | Gateway accepted the unique validation stream. |
| Synthetic LogQL query returns the log | Pass | Query returned the exact `softcon-loki-validation-20260825-224522` message. |

## Decision

Increment A accepted: Yes

Verification report: `/tmp/softcon-aiops-loki-20260825-224522.log`

## Increment B — Kubernetes log collection

| Check | Result | Evidence |
|---|---|---|
| Alloy discovers Kubernetes pods | Pass | Temporary validation pod was discovered in namespace `demo`. |
| Alloy reads Kubernetes container logs | Pass | Exact container output was collected. |
| Required bounded labels are present | Pass | Cluster, environment, namespace, app, pod, container, and job were returned. |
| Alloy sends container logs to Loki | Pass | Loki returned a successful streams result. |
| Unique validation-pod log is returned by LogQL | Pass | Query returned `softcon-kubernetes-log-20260825-230216`. |

## Decision

Increment B accepted: Yes

Verification report: `/tmp/softcon-aiops-kubernetes-logs-20260825-230216.log`

## Increment C — Grafana log exploration

| Check | Result | Evidence |
|---|---|---|
| Loki data source is provisioned | Pass | Read-only data source `loki` points to the in-cluster Loki gateway. |
| Grafana reports the Loki data source healthy | Pass | Health API returned `Data source successfully connected` with status `OK`. |
| Kubernetes log dashboard is provisioned | Pass | Dashboard `softcon-kubernetes-logs` is present in the SOFTCON AIOps folder. |
| Grafana proxy returns a Loki query | Pass | Query returned a live Loki gateway log collected by Alloy. |

## Decision

Increment C accepted: Yes

Verification report: `/tmp/softcon-aiops-grafana-logs-20260825-232213.log`

Grafana upgrade recovery used the `Recreate` strategy and disabled the redundant `init-chown-data` container. The original 5 GiB PVC remained Bound.
