# Platform monitoring validation

- Date: 2026-08-25
- Tester: Jesse Jadraque
- Host: UM780 XTX (`pop-os`)
- Branch: softcon-2027
- k3s: v1.36.3+k3s1
- Helm: v4.2.4
- kube-state-metrics: v2.20.0 (chart 8.4.0)

## Increment A — Kubernetes metrics

| Check | Result | Evidence |
|---|---|---|
| k3s Metrics Server is running | Pass | Deployment successfully rolled out in `kube-system`. |
| kubectl top nodes returns data | Pass | UM780 reported 337m CPU and 18,568 MiB memory during final verification. |
| kubectl top pods returns data | Pass | Resource data returned for workloads in `demo`, `kube-system`, and `observability`. |
| kube-state-metrics deployment is available | Pass | Deployment 1/1 available; pod Running with zero restarts. |
| kube-state-metrics endpoint returns kube metrics | Pass | Endpoint returned deployment metrics for system, demo, and observability workloads. |
| Foundation ingress remains available | Pass | `aiops-demo.local` returned HTTP 200. |

## Decision

Increment A accepted: Yes

## Evidence

Verification report generated on the host:

```text
/tmp/softcon-aiops-kubernetes-metrics-20260825-213229.log
```

The first port-forward connection attempt occurred before the listener was ready. The script retried successfully and completed verification.

## Increment B — Host metrics

| Check | Result | Evidence |
|---|---|---|
| Node Exporter DaemonSet is available | Pass | Desired, current, ready, and available all reported 1. |
| Node Exporter pod is running | Pass | Pod running on `pop-os` with zero restarts. |
| Node Exporter service is reachable | Pass | ClusterIP service exposed port 9100 and verification retrieved metrics. |
| CPU metrics are exposed | Pass | `node_cpu_seconds_total` was present. |
| Memory metrics are exposed | Pass | `node_memory_MemAvailable_bytes` reported approximately 40.5 GB available. |
| Filesystem metrics are exposed | Pass | Root filesystem reported approximately 442 GB available. |

## Decision

Increment B accepted: Yes

Verification report: `/tmp/softcon-aiops-node-exporter-20260825-214433.log`

Node Exporter also exposed temporary, tmpfs, and LM Studio AppImage FUSE mounts. These will be filtered in Alloy before remote write.
