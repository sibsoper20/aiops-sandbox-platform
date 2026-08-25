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
| Alloy discovers Kubernetes pods | Not run | |
| Alloy reads Kubernetes container logs | Not run | |
| Required bounded labels are present | Not run | |
| Alloy sends container logs to Loki | Not run | |
| Unique validation-pod log is returned by LogQL | Not run | |

## Decision

Increment B accepted: No

## Increment C — Grafana log exploration

Not started.
